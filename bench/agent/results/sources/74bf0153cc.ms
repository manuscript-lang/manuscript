import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"

enum Val:
	Null
	Int(i: Int)
	Text(s: String)
	Bool(b: Bool)

type Tok:
	k: Int
	s: String
	u: String
	n: Int = 0

type RawStmt:
	toks: List[Tok]
	bad: Bool

type Node:
	kind: String
	s: String = ""
	q: String = ""
	n: Int = 0
	kids: List[Int] = []

type ColDef:
	name: String
	is_int: Bool
	notnull: Bool
	pk: Bool

type TRef:
	name: String
	alias: String

type Join:
	left: Bool
	t: TRef
	on: Int

type Item:
	kind: Int
	q: String
	e: Int
	alias: String
	has_alias: Bool

type OrdItem:
	e: Int
	desc: Bool

type Stmt:
	kind: String = ""
	name: String = ""
	coldefs: List[ColDef] = []
	names: List[String] = []
	rows: List[List[Int]] = []
	sets: List[Int] = []
	cond: Int = -1
	distinct: Bool = false
	items: List[Item] = []
	from: List[TRef] = []
	joins: List[Join] = []
	group: List[Int] = []
	having: Int = -1
	order: List[OrdItem] = []
	limit: Int = -1
	offset: Int = -1

type Parsed:
	st: Stmt
	nodes: List[Node]

type Table:
	name: String
	cols: List[ColDef]
	rows: List[List[Val]]

type Db:
	tables: List[Table] = []

type ScopeCol:
	alias: String
	name: String

fn is_alpha(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
fn is_digit(c: Int) Bool: c >= 48 and c <= 57

fn lex_all(b: Bytes) List[RawStmt]:
	var out = List[RawStmt]()
	var toks = List[Tok]()
	var bad = false
	var i = 0
	n := b.length()
	while i < n:
		c := b.get(i).to_int()
		if c == 59:
			if toks.length() > 0 or bad:
				out.append(RawStmt(toks, bad))
			toks = List[Tok]()
			bad = false
			i += 1
		else if c == 32 or c == 9 or c == 13 or c == 10:
			i += 1
		else if c == 45 and i + 1 < n and b.get(i + 1).to_int() == 45:
			while i < n and b.get(i).to_int() != 10:
				i += 1
		else if is_alpha(c):
			start := i
			while i < n and (is_alpha(b.get(i).to_int()) or is_digit(b.get(i).to_int())):
				i += 1
			s := b.decode_utf8_range(start, i).get("")
			toks.append(Tok(0, s.clone(), s.upper()))
		else if is_digit(c):
			start := i
			while i < n and is_digit(b.get(i).to_int()):
				i += 1
			s := b.decode_utf8_range(start, i).get("")
			if v := s.parse_int():
				toks.append(Tok(1, s.clone(), s.clone(), v))
			else:
				bad = true
		else if c == 39:
			i += 1
			var bb = BytesBuilder()
			var closed = false
			while i < n:
				d := b.get(i)
				if d.to_int() == 39:
					if i + 1 < n and b.get(i + 1).to_int() == 39:
						bb.append(d)
						i += 2
					else:
						closed = true
						i += 1
						break
				else:
					bb.append(d)
					i += 1
			if closed:
				s := bb.build().decode_utf8().get("")
				toks.append(Tok(2, s.clone(), s.clone()))
			else:
				bad = true
		else:
			nx := if i + 1 < n: b.get(i + 1).to_int() else: 0
			if c == 60 and (nx == 62 or nx == 61):
				op := if nx == 62: "<>" else: "<="
				toks.append(Tok(3, op.clone(), op.clone()))
				i += 2
			else if c == 62 and nx == 61:
				toks.append(Tok(3, ">=", ">="))
				i += 2
			else if c == 33 and nx == 61:
				toks.append(Tok(3, "<>", "<>"))
				i += 2
			else if c == 124 and nx == 124:
				toks.append(Tok(3, "||", "||"))
				i += 2
			else if c == 61 or c == 60 or c == 62 or c == 43 or c == 45 or c == 42 or c == 47 or c == 37 or c == 40 or c == 41 or c == 44 or c == 46:
				op := b.decode_utf8_range(i, i + 1).get("")
				toks.append(Tok(3, op.clone(), op.clone()))
				i += 1
			else:
				bad = true
				i += 1
	if toks.length() > 0 or bad:
		out.append(RawStmt(toks, bad))
	return out

fn is_reserved(u: String) Bool:
	words := ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"]
	return words.contains(u)

type P:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = []

fn syn() Error: Error("syntax error")

fn P.kind() Int:
	if self.pos >= self.toks.length(): return 9
	return self.toks[self.pos].k

fn P.text() String:
	if self.pos >= self.toks.length(): return ""
	return self.toks[self.pos].s.clone()

fn P.up() String:
	if self.pos >= self.toks.length(): return ""
	return self.toks[self.pos].u.clone()

fn P.ival() Int:
	return self.toks[self.pos].n

fn P.is_kw(w: String) Bool:
	return self.kind() == 0 and self.up() == w

fn P.is_op(o: String) Bool:
	return self.kind() == 3 and self.text() == o

fn P.kw_at(off: Int, w: String) Bool:
	i := self.pos + off
	if i >= self.toks.length(): return false
	return self.toks[i].k == 0 and self.toks[i].u == w

fn P.op_at(off: Int, o: String) Bool:
	i := self.pos + off
	if i >= self.toks.length(): return false
	return self.toks[i].k == 3 and self.toks[i].s == o

fn P.kind_at(off: Int) Int:
	i := self.pos + off
	if i >= self.toks.length(): return 9
	return self.toks[i].k

fn var P.adv() Unit:
	self.pos += 1

fn var P.accept_kw(w: String) Bool:
	if self.is_kw(w):
		self.pos += 1
		return true
	return false

fn var P.accept_op(o: String) Bool:
	if self.is_op(o):
		self.pos += 1
		return true
	return false

fn var P.expect_kw(w: String) Unit!:
	if not self.accept_kw(w): return error(syn())

fn var P.expect_op(o: String) Unit!:
	if not self.accept_op(o): return error(syn())

fn var P.name() String!:
	if self.kind() != 0 or is_reserved(self.up()): return error(syn())
	s := self.text()
	self.pos += 1
	return ok(s)

fn var P.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var P.parse_or() Int!:
	var l = self.parse_and()?
	while self.accept_kw("OR"):
		r := self.parse_and()?
		l = self.add(Node(kind: "or", kids: [l, r]))
	return ok(l)

fn var P.parse_and() Int!:
	var l = self.parse_not()?
	while self.accept_kw("AND"):
		r := self.parse_not()?
		l = self.add(Node(kind: "and", kids: [l, r]))
	return ok(l)

fn var P.parse_not() Int!:
	if self.accept_kw("NOT"):
		e := self.parse_not()?
		return ok(self.add(Node(kind: "not", kids: [e])))
	return self.parse_cmp()

fn var P.parse_cmp() Int!:
	l := self.parse_add()?
	if self.kind() == 3:
		op := self.text()
		if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
			self.adv()
			r := self.parse_add()?
			return ok(self.add(Node(kind: "cmp", s: op, kids: [l, r])))
		return ok(l)
	if self.accept_kw("IS"):
		neg := self.accept_kw("NOT")
		self.expect_kw("NULL")?
		return ok(self.add(Node(kind: "isnull", n: if neg: 1 else: 0, kids: [l])))
	var neg = 0
	if self.is_kw("NOT"):
		if self.kw_at(1, "LIKE") or self.kw_at(1, "IN") or self.kw_at(1, "BETWEEN"):
			self.adv()
			neg = 1
		else:
			return error(syn())
	if self.accept_kw("LIKE"):
		r := self.parse_add()?
		return ok(self.add(Node(kind: "like", n: neg, kids: [l, r])))
	if self.accept_kw("IN"):
		self.expect_op("(")?
		var kids = [l]
		kids.append(self.parse_or()?)
		while self.accept_op(","):
			kids.append(self.parse_or()?)
		self.expect_op(")")?
		return ok(self.add(Node(kind: "in", n: neg, kids: kids)))
	if self.accept_kw("BETWEEN"):
		lo := self.parse_add()?
		self.expect_kw("AND")?
		hi := self.parse_add()?
		return ok(self.add(Node(kind: "between", n: neg, kids: [l, lo, hi])))
	return ok(l)

fn var P.parse_add() Int!:
	var l = self.parse_mul()?
	while self.is_op("+") or self.is_op("-") or self.is_op("||"):
		op := self.text()
		self.adv()
		r := self.parse_mul()?
		l = self.add(Node(kind: "arith", s: op, kids: [l, r]))
	return ok(l)

fn var P.parse_mul() Int!:
	var l = self.parse_unary()?
	while self.is_op("*") or self.is_op("/") or self.is_op("%"):
		op := self.text()
		self.adv()
		r := self.parse_unary()?
		l = self.add(Node(kind: "arith", s: op, kids: [l, r]))
	return ok(l)

fn var P.parse_unary() Int!:
	if self.accept_op("-"):
		e := self.parse_unary()?
		return ok(self.add(Node(kind: "neg", kids: [e])))
	return self.parse_primary()

fn var P.parse_primary() Int!:
	k := self.kind()
	if k == 1:
		v := self.ival()
		self.adv()
		return ok(self.add(Node(kind: "int", n: v)))
	if k == 2:
		s := self.text()
		self.adv()
		return ok(self.add(Node(kind: "str", s: s)))
	if self.accept_kw("NULL"):
		return ok(self.add(Node(kind: "null")))
	if self.accept_op("("):
		e := self.parse_or()?
		self.expect_op(")")?
		return ok(e)
	if k == 0:
		name := self.name()?
		if self.accept_op("("):
			fname := name.upper()
			var node = Node(kind: "call", s: fname.clone())
			if self.accept_kw("DISTINCT"):
				node.n = 1
				node.kids.append(self.parse_or()?)
			else if self.is_op("*"):
				if fname != "COUNT": return error(syn())
				self.adv()
				node.q = "*"
			else if not self.is_op(")"):
				node.kids.append(self.parse_or()?)
				while self.accept_op(","):
					node.kids.append(self.parse_or()?)
			self.expect_op(")")?
			return ok(self.add(node))
		if self.accept_op("."):
			col := self.name()?
			return ok(self.add(Node(kind: "col", q: name, s: col)))
		return ok(self.add(Node(kind: "col", s: name)))
	return error(syn())

fn var P.parse_tref() TRef!:
	name := self.name()?
	if self.accept_kw("AS"):
		a := self.name()?
		return ok(TRef(name.clone(), a))
	if self.kind() == 0 and not is_reserved(self.up()):
		a := self.name()?
		return ok(TRef(name.clone(), a))
	return ok(TRef(name.clone(), name.clone()))

fn var P.parse_colref() Int!:
	name := self.name()?
	if self.accept_op("."):
		col := self.name()?
		return ok(self.add(Node(kind: "col", q: name, s: col)))
	return ok(self.add(Node(kind: "col", s: name)))

fn var P.parse_select() Stmt!:
	var st = Stmt(kind: "select")
	if self.accept_kw("DISTINCT"): st.distinct = true
	while true:
		if self.accept_op("*"):
			st.items.append(Item(0, "", -1, "", false))
		else if self.kind() == 0 and self.op_at(1, ".") and self.op_at(2, "*"):
			q := self.name()?
			self.adv()
			self.adv()
			st.items.append(Item(1, q, -1, "", false))
		else:
			e := self.parse_or()?
			if self.accept_kw("AS"):
				a := self.name()?
				st.items.append(Item(2, "", e, a, true))
			else:
				st.items.append(Item(2, "", e, "", false))
		if not self.accept_op(","): break
	if self.accept_kw("FROM"):
		st.from.append(self.parse_tref()?)
		while self.is_kw("JOIN") or self.is_kw("LEFT") or self.is_kw("INNER"):
			left := self.is_kw("LEFT")
			if left or self.is_kw("INNER"): self.adv()
			self.expect_kw("JOIN")?
			t := self.parse_tref()?
			self.expect_kw("ON")?
			on := self.parse_or()?
			st.joins.append(Join(left, t, on))
	if self.accept_kw("WHERE"):
		st.cond = self.parse_or()?
	if self.accept_kw("GROUP"):
		self.expect_kw("BY")?
		st.group.append(self.parse_colref()?)
		while self.accept_op(","):
			st.group.append(self.parse_colref()?)
	if self.accept_kw("HAVING"):
		st.having = self.parse_or()?
	if self.accept_kw("ORDER"):
		self.expect_kw("BY")?
		while true:
			e := self.parse_or()?
			var desc = false
			if self.accept_kw("DESC"): desc = true
			else if self.accept_kw("ASC"): desc = false
			st.order.append(OrdItem(e, desc))
			if not self.accept_op(","): break
	if self.accept_kw("LIMIT"):
		if self.kind() != 1: return error(syn())
		st.limit = self.ival()
		self.adv()
		if self.accept_kw("OFFSET"):
			if self.kind() != 1: return error(syn())
			st.offset = self.ival()
			self.adv()
	return ok(st)

fn var P.parse_stmt() Stmt!:
	if self.accept_kw("SELECT"):
		return self.parse_select()
	if self.accept_kw("CREATE"):
		self.expect_kw("TABLE")?
		var st = Stmt(kind: "create")
		st.name = self.name()?
		self.expect_op("(")?
		while true:
			cn := self.name()?
			if self.kind() != 0: return error(syn())
			tu := self.up()
			if tu != "INT" and tu != "TEXT": return error(syn())
			self.adv()
			var cd = ColDef(cn, tu == "INT", false, false)
			while true:
				if self.accept_kw("PRIMARY"):
					self.expect_kw("KEY")?
					cd.pk = true
				else if self.accept_kw("NOT"):
					self.expect_kw("NULL")?
					cd.notnull = true
				else:
					break
			st.coldefs.append(cd)
			if not self.accept_op(","): break
		self.expect_op(")")?
		return ok(st)
	if self.accept_kw("DROP"):
		self.expect_kw("TABLE")?
		var st = Stmt(kind: "drop")
		st.name = self.name()?
		return ok(st)
	if self.accept_kw("INSERT"):
		self.expect_kw("INTO")?
		var st = Stmt(kind: "insert")
		st.name = self.name()?
		if self.accept_op("("):
			st.names.append(self.name()?)
			while self.accept_op(","):
				st.names.append(self.name()?)
			self.expect_op(")")?
		self.expect_kw("VALUES")?
		while true:
			self.expect_op("(")?
			var row = List[Int]()
			row.append(self.parse_or()?)
			while self.accept_op(","):
				row.append(self.parse_or()?)
			self.expect_op(")")?
			st.rows.append(row)
			if not self.accept_op(","): break
		return ok(st)
	if self.accept_kw("UPDATE"):
		var st = Stmt(kind: "update")
		st.name = self.name()?
		self.expect_kw("SET")?
		while true:
			st.names.append(self.name()?)
			self.expect_op("=")?
			st.sets.append(self.parse_or()?)
			if not self.accept_op(","): break
		if self.accept_kw("WHERE"):
			st.cond = self.parse_or()?
		return ok(st)
	if self.accept_kw("DELETE"):
		self.expect_kw("FROM")?
		var st = Stmt(kind: "delete")
		st.name = self.name()?
		if self.accept_kw("WHERE"):
			st.cond = self.parse_or()?
		return ok(st)
	return error(syn())

fn parse(toks: List[Tok]) Parsed!:
	var p = P(toks)
	st := p.parse_stmt()?
	if p.pos < p.toks.length(): return error(syn())
	return ok(Parsed(st, p.nodes))

fn terr() Error: Error("type error")

fn show(v: Val) String:
	match v:
		Null: return "NULL"
		Int(i): return "{i}"
		Text(s): return s.clone()
		Bool(b): return if b: "true" else: "false"

fn key_of(v: Val) String:
	match v:
		Null: return "N;"
		Int(i): return "I{i};"
		Text(s): return "T{s.length()}:{s};"
		Bool(b): return if b: "Bt;" else: "Bf;"

fn row_key(vals: List[Val]) String:
	var s = ""
	for v in vals:
		s = s.concat(key_of(v))
	return s

fn rank(v: Val) Int:
	match v:
		Null: return 0
		Bool(_b): return 1
		Int(_i): return 2
		Text(_s): return 3

fn order_cmp(a: Val, b: Val) Int:
	ra := rank(a)
	rb := rank(b)
	if ra != rb: return if ra < rb: -1 else: 1
	match a:
		Int(x):
			match b:
				Int(y): return if x < y: -1 else if x > y: 1 else: 0
				_: return 0
		Text(x):
			match b:
				Text(y): return if x < y: -1 else if x > y: 1 else: 0
				_: return 0
		Bool(x):
			match b:
				Bool(y): return if x == y: 0 else if y: -1 else: 1
				_: return 0
		_: return 0

fn is_null(v: Val) Bool:
	match v:
		Null: return true
		_: return false

fn colname(nd: Node) String:
	if nd.q == "": return nd.s.clone()
	return "{nd.q}.{nd.s}"

fn is_agg(n: String) Bool: n == "COUNT" or n == "SUM" or n == "MIN" or n == "MAX"

fn resolve(scope: List[ScopeCol], q: String, name: String) Int!:
	var found = -1
	var count = 0
	for i in 0..scope.length():
		sc := scope[i]
		if sc.name == name and (q == "" or sc.alias == q):
			if count == 0: found = i
			count += 1
	if count == 0:
		if q == "": return error(Error("no such column: {name}"))
		return error(Error("no such column: {q}.{name}"))
	if count > 1: return error(Error("ambiguous column: {name}"))
	return ok(found)

type Cx:
	scope: List[ScopeCol]
	allow_agg: Bool
	grouped: Bool
	gidx: List[Int]

fn has_agg(nodes: List[Node], id: Int) Bool:
	nd := nodes[id]
	if nd.kind == "call" and is_agg(nd.s): return true
	for k in nd.kids:
		if has_agg(nodes, k): return true
	return false

fn arity_ok(f: String, n: Int) Bool:
	if f == "UPPER" or f == "LOWER" or f == "LENGTH" or f == "ABS": return n == 1
	if f == "SUBSTR": return n == 3
	if f == "COALESCE": return n >= 1
	return false

fn is_scalar_fn(f: String) Bool:
	return f == "UPPER" or f == "LOWER" or f == "LENGTH" or f == "ABS" or f == "SUBSTR" or f == "COALESCE"

fn check(nodes: List[Node], cx: Cx, id: Int, in_agg: Bool) Unit!:
	nd := nodes[id]
	if nd.kind == "col":
		idx := resolve(cx.scope, nd.q, nd.s)?
		if cx.grouped and not in_agg and not cx.gidx.contains(idx):
			return error(Error("column {colname(nd)} must appear in GROUP BY"))
		return ok(unit)
	if nd.kind == "call":
		if is_agg(nd.s):
			if not cx.allow_agg or in_agg: return error(Error("misuse of aggregate"))
			cnt := if nd.q == "*": 1 else: nd.kids.length()
			if cnt != 1: return error(Error("wrong number of arguments to {nd.s}"))
			for k in nd.kids:
				check(nodes, cx, k, true)?
			return ok(unit)
		if not is_scalar_fn(nd.s): return error(Error("no such function: {nd.s}"))
		if not arity_ok(nd.s, nd.kids.length()): return error(Error("wrong number of arguments to {nd.s}"))
	for k in nd.kids:
		check(nodes, cx, k, in_agg)?
	return ok(unit)

// three-valued: 0 false, 1 true, 2 null
fn tri(v: Val) Int!:
	match v:
		Null: return ok(2)
		Bool(b): return ok(if b: 1 else: 0)
		_: return error(terr())

fn mk_bool(t: Int) Val:
	if t == 2: return Val.Null
	return Val.Bool(t == 1)

fn cmp_vals(op: String, a: Val, b: Val) Val!:
	if is_null(a) or is_null(b): return ok(Val.Null)
	var c = 0
	match a:
		Int(x):
			match b:
				Int(y): c = if x < y: -1 else if x > y: 1 else: 0
				_: return error(terr())
		Text(x):
			match b:
				Text(y): c = if x < y: -1 else if x > y: 1 else: 0
				_: return error(terr())
		_: return error(terr())
	r := if op == "=": c == 0 else if op == "<>": c != 0 else if op == "<": c < 0 else if op == "<=": c <= 0 else if op == ">": c > 0 else: c >= 0
	return ok(Val.Bool(r))

fn arith(op: String, a: Val, b: Val) Val!:
	if is_null(a) or is_null(b): return ok(Val.Null)
	if op == "||":
		match a:
			Text(x):
				match b:
					Text(y): return ok(Val.Text(x.concat(y)))
					_: return error(terr())
			_: return error(terr())
	match a:
		Int(x):
			match b:
				Int(y):
					if op == "+": return ok(Val.Int(x + y))
					if op == "-": return ok(Val.Int(x - y))
					if op == "*": return ok(Val.Int(x * y))
					if y == 0: return error(Error("division by zero"))
					if op == "/": return ok(Val.Int(x / y))
					return ok(Val.Int(x % y))
				_: return error(terr())
		_: return error(terr())

fn like_match(s: Bytes, p: Bytes) Bool:
	var si = 0
	var pi = 0
	var star = -1
	var mark = 0
	sn := s.length()
	pn := p.length()
	while si < sn:
		if pi < pn and p.get(pi).to_int() == 37:
			star = pi
			mark = si
			pi += 1
		else if pi < pn and (p.get(pi).to_int() == 95 or p.get(pi) == s.get(si)):
			pi += 1
			si += 1
		else if star >= 0:
			pi = star + 1
			mark += 1
			si = mark
		else:
			return false
	while pi < pn and p.get(pi).to_int() == 37:
		pi += 1
	return pi == pn

fn ascii_map(s: String, up: Bool) String:
	b := s.to_bytes()
	var bb = BytesBuilder()
	for i in 0..b.length():
		c := b.get(i).to_int()
		if up and c >= 97 and c <= 122:
			bb.append((c - 32).to_uint8().get(0))
		else if not up and c >= 65 and c <= 90:
			bb.append((c + 32).to_uint8().get(0))
		else:
			bb.append(b.get(i))
	return bb.build().decode_utf8().get("")

fn eval_fn(name: String, args: List[Val]) Val!:
	if name == "COALESCE":
		for a in args:
			if not is_null(a): return ok(a.clone())
		return ok(Val.Null)
	for a in args:
		if is_null(a): return ok(Val.Null)
	a0 := args[0]
	if name == "UPPER" or name == "LOWER":
		match a0:
			Text(s): return ok(Val.Text(ascii_map(s, name == "UPPER")))
			_: return error(terr())
	if name == "LENGTH":
		match a0:
			Text(s): return ok(Val.Int(s.length()))
			_: return error(terr())
	if name == "ABS":
		match a0:
			Int(i): return ok(Val.Int(if i < 0: 0 - i else: i))
			_: return error(terr())
	// SUBSTR
	match a0:
		Text(s):
			match args[1]:
				Int(st):
					match args[2]:
						Int(ln):
							if ln <= 0: return ok(Val.Text(""))
							n := s.length()
							var lo = st
							var hi = st + ln
							if lo < 1: lo = 1
							if hi > n + 1: hi = n + 1
							if lo >= hi: return ok(Val.Text(""))
							r := s.to_bytes().decode_utf8_range(lo - 1, hi - 1).get("")
							return ok(Val.Text(r))
						_: return error(terr())
				_: return error(terr())
		_: return error(terr())

fn eval_agg(nodes: List[Node], scope: List[ScopeCol], nd: Node, grp: List[List[Val]]) Val!:
	if nd.q == "*": return ok(Val.Int(grp.length()))
	var vals = List[Val]()
	var seen = Set[String]()
	empty := List[List[Val]]()
	for r in grp:
		v := eval(nodes, scope, nd.kids[0], r, empty, false)?
		if is_null(v): continue
		if nd.n == 1:
			kk := key_of(v)
			if seen.contains(kk): continue
			seen.add(kk)
		vals.append(v)
	if nd.s == "COUNT": return ok(Val.Int(vals.length()))
	if vals.length() == 0: return ok(Val.Null)
	if nd.s == "SUM":
		var total = 0
		for v in vals:
			match v:
				Int(i): total += i
				_: return error(terr())
		return ok(Val.Int(total))
	var best = vals[0].clone()
	var first = true
	for v in vals:
		if first:
			first = false
			match v:
				Int(_i): unit
				Text(_s): unit
				_: return error(terr())
			continue
		r := cmp_vals("<", v, best)?
		match r:
			Bool(lt):
				c2 := cmp_vals(">", v, best)?
				match c2:
					Bool(gt):
						if nd.s == "MIN" and lt: best = v.clone()
						if nd.s == "MAX" and gt: best = v.clone()
					_: unit
			_: unit
	return ok(best)

fn eval(nodes: List[Node], scope: List[ScopeCol], id: Int, row: List[Val], grp: List[List[Val]], isg: Bool) Val!:
	nd := nodes[id]
	k := nd.kind
	if k == "int": return ok(Val.Int(nd.n))
	if k == "str": return ok(Val.Text(nd.s.clone()))
	if k == "null": return ok(Val.Null)
	if k == "col":
		idx := resolve(scope, nd.q, nd.s)?
		return ok(row.get(idx, Val.Null).clone())
	if k == "neg":
		v := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		match v:
			Null: return ok(Val.Null)
			Int(i): return ok(Val.Int(0 - i))
			_: return error(terr())
	if k == "and":
		a := tri(eval(nodes, scope, nd.kids[0], row, grp, isg)?)?
		if a == 0: return ok(Val.Bool(false))
		b := tri(eval(nodes, scope, nd.kids[1], row, grp, isg)?)?
		if b == 0: return ok(Val.Bool(false))
		if a == 2 or b == 2: return ok(Val.Null)
		return ok(Val.Bool(true))
	if k == "or":
		a := tri(eval(nodes, scope, nd.kids[0], row, grp, isg)?)?
		if a == 1: return ok(Val.Bool(true))
		b := tri(eval(nodes, scope, nd.kids[1], row, grp, isg)?)?
		if b == 1: return ok(Val.Bool(true))
		if a == 2 or b == 2: return ok(Val.Null)
		return ok(Val.Bool(false))
	if k == "not":
		a := tri(eval(nodes, scope, nd.kids[0], row, grp, isg)?)?
		if a == 2: return ok(Val.Null)
		return ok(Val.Bool(a == 0))
	if k == "cmp":
		a := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		b := eval(nodes, scope, nd.kids[1], row, grp, isg)?
		return cmp_vals(nd.s, a, b)
	if k == "arith":
		a := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		b := eval(nodes, scope, nd.kids[1], row, grp, isg)?
		return arith(nd.s, a, b)
	if k == "isnull":
		a := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		r := is_null(a)
		return ok(Val.Bool(if nd.n == 1: not r else: r))
	if k == "like":
		a := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		b := eval(nodes, scope, nd.kids[1], row, grp, isg)?
		if is_null(a) or is_null(b): return ok(Val.Null)
		match a:
			Text(x):
				match b:
					Text(y):
						m := like_match(x.to_bytes(), y.to_bytes())
						return ok(Val.Bool(if nd.n == 1: not m else: m))
					_: return error(terr())
			_: return error(terr())
	if k == "in":
		x := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		var res = 0
		var sawnull = false
		for i in 1..nd.kids.length():
			e := eval(nodes, scope, nd.kids[i], row, grp, isg)?
			if is_null(x): continue
			if is_null(e):
				sawnull = true
				continue
			c := cmp_vals("=", x, e)?
			match c:
				Bool(t):
					if t:
						res = 1
						break
				_: unit
		if is_null(x): return ok(Val.Null)
		var t = 0
		if res == 1: t = 1
		else if sawnull: t = 2
		if nd.n == 1:
			if t == 2: return ok(Val.Null)
			t = 1 - t
		return ok(mk_bool(t))
	if k == "between":
		x := eval(nodes, scope, nd.kids[0], row, grp, isg)?
		lo := eval(nodes, scope, nd.kids[1], row, grp, isg)?
		hi := eval(nodes, scope, nd.kids[2], row, grp, isg)?
		a := tri(cmp_vals(">=", x, lo)?)?
		var t = 0
		if a == 0:
			t = 0
		else:
			b := tri(cmp_vals("<=", x, hi)?)?
			if b == 0: t = 0
			else if a == 2 or b == 2: t = 2
			else: t = 1
		if nd.n == 1:
			if t == 2: return ok(Val.Null)
			t = 1 - t
		return ok(mk_bool(t))
	// call
	if is_agg(nd.s):
		return eval_agg(nodes, scope, nd, grp)
	var args = List[Val]()
	for a in nd.kids:
		args.append(eval(nodes, scope, a, row, grp, isg)?)
	return eval_fn(nd.s, args)

fn truthy(v: Val) Bool!:
	t := tri(v)?
	return ok(t == 1)

type OutCol:
	name: String
	e: Int
	col: Int

type Src:
	row: List[Val]
	grp: List[List[Val]]

type Out:
	vals: List[Val]
	keys: List[Val]
	src: Int

fn find_table(db: Db, name: String) Int:
	for i in 0..db.tables.length():
		if db.tables[i].name == name: return i
	return -1

fn check_row(cols: List[ColDef], row: List[Val]) Unit!:
	for i in 0..cols.length():
		c := cols[i]
		v := row[i]
		if is_null(v):
			if c.notnull or c.pk: return error(Error("NOT NULL constraint failed: {c.name}"))
		else:
			var good = false
			match v:
				Int(_i): good = c.is_int
				Text(_s): good = not c.is_int
				_: good = false
			if not good: return error(Error("type mismatch in column {c.name}"))

fn dup_pk(cols: List[ColDef], rows: List[List[Val]]) Unit!:
	var pk = -1
	for i in 0..cols.length():
		if cols[i].pk: pk = i
	if pk < 0: return ok(unit)
	var seen = Set[String]()
	for r in rows:
		kk := key_of(r[pk])
		if seen.contains(kk): return error(Error("duplicate primary key: {show(r[pk])}"))
		seen.add(kk)

fn table_scope(alias: String, cols: List[ColDef]) List[ScopeCol]:
	var sc = List[ScopeCol]()
	for c in cols:
		sc.append(ScopeCol(alias.clone(), c.name.clone()))
	return sc

fn prefix(scope: List[ScopeCol], n: Int) List[ScopeCol]:
	var out = List[ScopeCol]()
	for i in 0..n:
		out.append(ScopeCol(scope[i].alias.clone(), scope[i].name.clone()))
	return out

fn nulls_row() List[Val]: List[Val]()

fn run_select(db: Db, ps: Parsed) List[String]!:
	st := ps.st
	nodes := ps.nodes
	var all_t = List[TRef]()
	if st.from.length() > 0:
		all_t.append(TRef(st.from[0].name.clone(), st.from[0].alias.clone()))
	for j in st.joins:
		all_t.append(TRef(j.t.name.clone(), j.t.alias.clone()))
	for t in all_t:
		if find_table(db, t.name) < 0: return error(Error("no such table: {t.name}"))
	var aliases = Set[String]()
	for t in all_t:
		if aliases.contains(t.alias): return error(Error("duplicate alias: {t.alias}"))
		aliases.add(t.alias.clone())
	var scope = List[ScopeCol]()
	var ends = List[Int]()
	ends.append(0)
	var starts = List[Int]()
	for t in all_t:
		starts.append(scope.length())
		tb := db.tables[find_table(db, t.name)]
		for c in tb.cols:
			scope.append(ScopeCol(t.alias.clone(), c.name.clone()))
		ends.append(scope.length())
	// join conditions
	for ji in 0..st.joins.length():
		cxj := Cx(prefix(scope, ends[ji + 2]), false, false, [])
		check(nodes, cxj, st.joins[ji].on, false)?
	// stars
	for it in st.items:
		if it.kind == 1:
			var found = false
			for t in all_t:
				if t.alias == it.q: found = true
			if not found: return error(Error("no such table: {it.q}"))
	// group by
	var gidx = List[Int]()
	cx0 := Cx(prefix(scope, scope.length()), false, false, [])
	for g in st.group:
		check(nodes, cx0, g, false)?
		gn := nodes[g]
		gidx.append(resolve(scope, gn.q, gn.s)?)
	if st.cond >= 0:
		check(nodes, cx0, st.cond, false)?
	var aggregated = st.group.length() > 0 or st.having >= 0
	for it in st.items:
		if it.kind == 2 and has_agg(nodes, it.e): aggregated = true
	for o in st.order:
		if has_agg(nodes, o.e): aggregated = true
	cxs := Cx(prefix(scope, scope.length()), true, aggregated, gidx.clone())
	var outs = List[OutCol]()
	for it in st.items:
		if it.kind == 2:
			check(nodes, cxs, it.e, false)?
			nm := if it.has_alias: it.alias.clone() else if nodes[it.e].kind == "col": nodes[it.e].s.clone() else: "?column?"
			outs.append(OutCol(nm, it.e, -1))
		else:
			for ti in 0..all_t.length():
				if it.kind == 0 or all_t[ti].alias == it.q:
					for ci in starts[ti]..ends[ti + 1]:
						if aggregated and not gidx.contains(ci):
							return error(Error("column {scope[ci].name} must appear in GROUP BY"))
						outs.append(OutCol(scope[ci].name.clone(), -1, ci))
	if st.having >= 0:
		check(nodes, cxs, st.having, false)?
	var ord_col = List[Int]()
	for o in st.order:
		on := nodes[o.e]
		if on.kind == "int":
			if on.n < 1 or on.n > outs.length(): return error(Error("bad ORDER BY position"))
			ord_col.append(on.n - 1)
		else:
			var m = -1
			if on.kind == "col" and on.q == "":
				for i in 0..outs.length():
					if m < 0 and outs[i].name == on.s: m = i
			if m < 0:
				check(nodes, cxs, o.e, false)?
			ord_col.append(m)
	// rows
	var cur = List[List[Val]]()
	if all_t.length() == 0:
		cur.append(List[Val]())
	else:
		for r in db.tables[find_table(db, all_t[0].name)].rows:
			cur.append(r.clone())
	empty := List[List[Val]]()
	for ji in 0..st.joins.length():
		jt := db.tables[find_table(db, all_t[ji + 1].name)]
		pscope := prefix(scope, ends[ji + 2])
		var nxt = List[List[Val]]()
		for o in cur:
			var matched = false
			for ir in jt.rows:
				var comb = o.clone()
				for v in ir:
					comb.append(v.clone())
				c := truthy(eval(nodes, pscope, st.joins[ji].on, comb, empty, false)?)?
				if c:
					matched = true
					nxt.append(comb)
			if st.joins[ji].left and not matched:
				var comb = o.clone()
				for _c in jt.cols:
					comb.append(Val.Null)
				nxt.append(comb)
		cur = nxt
	var filtered = List[List[Val]]()
	for r in cur:
		if st.cond >= 0:
			c := truthy(eval(nodes, scope, st.cond, r, empty, false)?)?
			if not c: continue
		filtered.append(r.clone())
	var srcs = List[Src]()
	if aggregated:
		var groups = List[List[List[Val]]]()
		if st.group.length() == 0:
			var g = List[List[Val]]()
			for r in filtered:
				g.append(r.clone())
			groups.append(g)
		else:
			var index = Map[String, Int]()
			for r in filtered:
				var kv = List[Val]()
				for gi in gidx:
					kv.append(r[gi].clone())
				kk := row_key(kv)
				if gx := index.get(kk):
					groups[gx].append(r.clone())
				else:
					index[kk] = groups.length()
					var g = List[List[Val]]()
					g.append(r.clone())
					groups.append(g)
		for g in groups:
			row := if g.length() > 0: g[0].clone() else: List[Val]()
			if st.having >= 0:
				h := truthy(eval(nodes, scope, st.having, row, g, true)?)?
				if not h: continue
			srcs.append(Src(row, g.clone()))
	else:
		for r in filtered:
			srcs.append(Src(r.clone(), List[List[Val]]()))
	// select
	var outrows = List[Out]()
	var seen = Set[String]()
	for si in 0..srcs.length():
		s := srcs[si]
		var vals = List[Val]()
		for oc in outs:
			if oc.e >= 0:
				vals.append(eval(nodes, scope, oc.e, s.row, s.grp, aggregated)?)
			else:
				vals.append(s.row.get(oc.col, Val.Null).clone())
		if st.distinct:
			kk := row_key(vals)
			if seen.contains(kk): continue
			seen.add(kk)
		outrows.append(Out(vals, List[Val](), si))
	if st.order.length() > 0:
		for oi in 0..outrows.length():
			s := srcs[outrows[oi].src]
			var keys = List[Val]()
			for j in 0..st.order.length():
				if ord_col[j] >= 0:
					keys.append(outrows[oi].vals[ord_col[j]].clone())
				else:
					keys.append(eval(nodes, scope, st.order[j].e, s.row, s.grp, aggregated)?)
			outrows[oi].keys = keys
		var descs = List[Bool]()
		for o in st.order:
			descs.append(o.desc)
		outrows.sort(fn a, b: cmp_keys(a, b, descs))
	var lines = List[String]()
	var names = List[String]()
	for oc in outs:
		names.append(oc.name.clone())
	lines.append(names.join("|"))
	var from_i = 0
	if st.offset >= 0: from_i = st.offset
	var count = 0
	for i in from_i..outrows.length():
		if st.limit >= 0 and count >= st.limit: break
		var parts = List[String]()
		for v in outrows[i].vals:
			parts.append(show(v))
		lines.append(parts.join("|"))
		count += 1
	lines.append("({count} rows)")
	return ok(lines)

fn cmp_keys(a: Out, b: Out, descs: List[Bool]) Int:
	for i in 0..descs.length():
		c := order_cmp(a.keys[i], b.keys[i])
		if c != 0: return if descs[i]: 0 - c else: c
	return 0

fn exec(var db: Db, ps: Parsed) List[String]!:
	st := ps.st
	nodes := ps.nodes
	var res = List[String]()
	if st.kind == "select":
		return run_select(db, ps)
	if st.kind == "create":
		if find_table(db, st.name) >= 0: return error(Error("table {st.name} already exists"))
		var names = Set[String]()
		var pks = 0
		var cols = List[ColDef]()
		for c in st.coldefs:
			if names.contains(c.name): return error(Error("duplicate column: {c.name}"))
			names.add(c.name.clone())
			if c.pk: pks += 1
			cols.append(ColDef(c.name.clone(), c.is_int, c.notnull or c.pk, c.pk))
		if pks > 1: return error(Error("multiple primary keys"))
		db.tables.append(Table(st.name.clone(), cols, List[List[Val]]()))
		res.append("ok")
		return ok(res)
	ti := find_table(db, st.name)
	if ti < 0: return error(Error("no such table: {st.name}"))
	if st.kind == "drop":
		db.tables.remove(ti)
		res.append("ok")
		return ok(res)
	cols := db.tables[ti].cols.clone()
	empty := List[List[Val]]()
	noscope := List[ScopeCol]()
	if st.kind == "insert":
		var tgt = List[Int]()
		if st.names.length() == 0:
			for i in 0..cols.length():
				tgt.append(i)
		else:
			for nm in st.names:
				var idx = -1
				for i in 0..cols.length():
					if cols[i].name == nm: idx = i
				if idx < 0: return error(Error("no such column: {nm}"))
				if tgt.contains(idx): return error(Error("duplicate column: {nm}"))
				tgt.append(idx)
		cx := Cx(noscope.clone(), false, false, [])
		var newrows = List[List[Val]]()
		for r in st.rows:
			if r.length() != tgt.length(): return error(Error("wrong number of values"))
			for e in r:
				check(nodes, cx, e, false)?
			var row = List[Val]()
			for _c in cols:
				row.append(Val.Null)
			for j in 0..r.length():
				row[tgt[j]] = eval(nodes, noscope, r[j], row.clone(), empty, false)?
			check_row(cols, row)?
			newrows.append(row)
		var all = db.tables[ti].rows.clone()
		n := newrows.length()
		for r in newrows:
			all.append(r.clone())
		dup_pk(cols, all)?
		db.tables[ti].rows = all
		res.append("inserted {n}")
		return ok(res)
	scope := table_scope(st.name, cols)
	cx := Cx(scope.clone(), false, false, [])
	if st.kind == "update":
		var idxs = List[Int]()
		for nm in st.names:
			var idx = -1
			for i in 0..cols.length():
				if cols[i].name == nm: idx = i
			if idx < 0: return error(Error("no such column: {nm}"))
			idxs.append(idx)
		for e in st.sets:
			check(nodes, cx, e, false)?
		if st.cond >= 0:
			check(nodes, cx, st.cond, false)?
		var newrows = List[List[Val]]()
		var count = 0
		for r in db.tables[ti].rows:
			var hit = true
			if st.cond >= 0:
				hit = truthy(eval(nodes, scope, st.cond, r, empty, false)?)?
			if hit:
				var nr = r.clone()
				for j in 0..idxs.length():
					nr[idxs[j]] = eval(nodes, scope, st.sets[j], r, empty, false)?
				check_row(cols, nr)?
				newrows.append(nr)
				count += 1
			else:
				newrows.append(r.clone())
		dup_pk(cols, newrows)?
		db.tables[ti].rows = newrows
		res.append("updated {count}")
		return ok(res)
	// delete
	if st.cond >= 0:
		check(nodes, cx, st.cond, false)?
	var keep = List[List[Val]]()
	var count = 0
	for r in db.tables[ti].rows:
		var hit = true
		if st.cond >= 0:
			hit = truthy(eval(nodes, scope, st.cond, r, empty, false)?)?
		if hit:
			count += 1
		else:
			keep.append(r.clone())
	db.tables[ti].rows = keep
	res.append("deleted {count}")
	return ok(res)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	var db = Db()
	for raw in lex_all(data):
		if raw.bad:
			print("error: syntax error")
			continue
		parsed := parse(raw.toks.clone())
		if ps := parsed:
			r := exec(var db, ps)
			if lines := r:
				for l in lines:
					print(l)
			else:
				print("error: {r.err().message}")
		else:
			print("error: {parsed.err().message}")
