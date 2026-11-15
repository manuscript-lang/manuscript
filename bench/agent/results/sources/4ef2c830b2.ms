import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Val:
	k: Int
	i: Int = 0
	s: String = ""

fn vnull() Val: Val(k: 0)
fn vint(n: Int) Val: Val(k: 1, i: n)
fn vtext(s: String) Val: Val(k: 2, s: s)
fn vbool(b: Bool) Val:
	if b: return Val(k: 3, i: 1)
	return Val(k: 3, i: 0)

fn show(v: Val) String:
	if v.k == 0: return "NULL"
	if v.k == 1: return "{v.i}"
	if v.k == 2: return v.s.clone()
	if v.i == 1: return "true"
	return "false"

fn vkey(v: Val) String:
	if v.k == 0: return "N;"
	if v.k == 1: return "I{v.i};"
	if v.k == 2: return "T{v.s.length()}:{v.s};"
	return "B{v.i};"

fn rowkey(vals: List[Val]) String:
	var out = ""
	for v in vals:
		out += vkey(v)
	return out

fn fail(msg: String) Error: Error(msg)

// ---------- lexer ----------

type Tok:
	kind: Int
	text: String = ""
	n: Int = 0

fn is_kw(s: String) Bool:
	kws := ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"]
	return kws.contains(s)

fn is_digit(c: String) Bool: c >= "0" and c <= "9"
fn is_alpha(c: String) Bool: (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

// kinds: 0 ident, 1 keyword, 2 int, 3 string, 4 op, 5 eof
fn lex(text: String) List[Tok]!:
	cs := text.chars()
	var toks: List[Tok] = []
	var i = 0
	n := cs.length()
	while i < n:
		c := cs[i]
		if c == " " or c == "\t" or c == "\r" or c == "\n":
			i += 1
			continue
		if c == "-" and i + 1 < n and cs[i + 1] == "-":
			while i < n and cs[i] != "\n":
				i += 1
			continue
		if is_alpha(c):
			var w = ""
			while i < n and (is_alpha(cs[i]) or is_digit(cs[i])):
				w += cs[i]
				i += 1
			up := w.upper()
			if is_kw(up):
				toks.append(Tok(kind: 1, text: up))
			else:
				toks.append(Tok(kind: 0, text: w))
			continue
		if is_digit(c):
			var w = ""
			while i < n and is_digit(cs[i]):
				w += cs[i]
				i += 1
			if v := w.parse_int():
				toks.append(Tok(kind: 2, n: v))
			else:
				return error(fail("syntax error"))
			continue
		if c == "'":
			i += 1
			var w = ""
			var closed = false
			while i < n:
				if cs[i] == "'":
					if i + 1 < n and cs[i + 1] == "'":
						w += "'"
						i += 2
						continue
					closed = true
					i += 1
					break
				w += cs[i]
				i += 1
			if not closed:
				return error(fail("syntax error"))
			toks.append(Tok(kind: 3, text: w))
			continue
		if i + 1 < n:
			two := c + cs[i + 1]
			if two == "<>" or two == "!=" or two == "<=" or two == ">=" or two == "||":
				if two == "!=":
					toks.append(Tok(kind: 4, text: "<>"))
				else:
					toks.append(Tok(kind: 4, text: two))
				i += 2
				continue
		if c == "=" or c == "<" or c == ">" or c == "+" or c == "-" or c == "*" or c == "/" or c == "%" or c == "(" or c == ")" or c == "," or c == ".":
			toks.append(Tok(kind: 4, text: c.clone()))
			i += 1
			continue
		return error(fail("syntax error"))
	toks.append(Tok(kind: 5))
	return ok(toks)

// ---------- AST ----------

type Node:
	kind: String
	op: String = ""
	q: String = ""
	i: Int = 0
	s: String = ""
	flag: Bool = false
	kids: List[Int] = []

type ColDef:
	name: String
	is_int: Bool
	notnull: Bool
	pk: Bool

type Item:
	kind: String
	q: String = ""
	expr: Int = -1
	alias: String = ""
	has_alias: Bool = false

type Tref:
	name: String
	alias: String

type OrdItem:
	expr: Int
	desc: Bool

type Stmt:
	kind: String
	name: String = ""
	coldefs: List[ColDef] = []
	names: List[String] = []
	has_names: Bool = false
	rows: List[List[Int]] = []
	exprs: List[Int] = []
	where: Int = -1
	distinct: Bool = false
	items: List[Item] = []
	trefs: List[Tref] = []
	left: List[Bool] = []
	ons: List[Int] = []
	group: List[Int] = []
	having: Int = -1
	order: List[OrdItem] = []
	limit: Int = -1
	offset: Int = 0

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = []

fn syn() Error: Error("syntax error")

fn Parser.kind() Int: self.toks[self.pos].kind
fn Parser.text() String: self.toks[self.pos].text.clone()
fn Parser.num() Int: self.toks[self.pos].n
fn Parser.is_kw(w: String) Bool: self.toks[self.pos].kind == 1 and self.toks[self.pos].text == w
fn Parser.is_op(o: String) Bool: self.toks[self.pos].kind == 4 and self.toks[self.pos].text == o
fn Parser.next_is_op(o: String) Bool:
	if self.pos + 1 >= self.toks.length(): return false
	return self.toks[self.pos + 1].kind == 4 and self.toks[self.pos + 1].text == o
fn var Parser.adv() Unit:
	if self.pos < self.toks.length() - 1:
		self.pos += 1
fn var Parser.eat_kw(w: String) Bool:
	if self.is_kw(w):
		self.adv()
		return true
	return false
fn var Parser.eat_op(o: String) Bool:
	if self.is_op(o):
		self.adv()
		return true
	return false
fn var Parser.expect_kw(w: String) Unit!:
	if self.eat_kw(w): return ok(unit)
	return error(syn())
fn var Parser.expect_op(o: String) Unit!:
	if self.eat_op(o): return ok(unit)
	return error(syn())
fn var Parser.ident() String!:
	if self.kind() == 0:
		t := self.text()
		self.adv()
		return ok(t)
	return error(syn())
fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var Parser.parse_expr() Int!:
	var l = self.parse_and()?
	while self.eat_kw("OR"):
		r := self.parse_and()?
		l = self.add(Node(kind: "or", kids: [l, r]))
	return ok(l)

fn var Parser.parse_and() Int!:
	var l = self.parse_not()?
	while self.eat_kw("AND"):
		r := self.parse_not()?
		l = self.add(Node(kind: "and", kids: [l, r]))
	return ok(l)

fn var Parser.parse_not() Int!:
	if self.eat_kw("NOT"):
		x := self.parse_not()?
		return ok(self.add(Node(kind: "not", kids: [x])))
	return self.parse_cmp()

fn var Parser.parse_cmp() Int!:
	l := self.parse_add()?
	if self.kind() == 4:
		t := self.text()
		if t == "=" or t == "<>" or t == "<" or t == "<=" or t == ">" or t == ">=":
			self.adv()
			r := self.parse_add()?
			return ok(self.add(Node(kind: "cmp", op: t, kids: [l, r])))
		return ok(l)
	if self.eat_kw("IS"):
		neg := self.eat_kw("NOT")
		self.expect_kw("NULL")?
		return ok(self.add(Node(kind: "isnull", flag: neg, kids: [l])))
	var neg = false
	if self.is_kw("NOT"):
		self.adv()
		neg = true
		if not (self.is_kw("LIKE") or self.is_kw("IN") or self.is_kw("BETWEEN")):
			return error(syn())
	if self.eat_kw("LIKE"):
		r := self.parse_add()?
		return ok(self.add(Node(kind: "like", flag: neg, kids: [l, r])))
	if self.eat_kw("IN"):
		self.expect_op("(")?
		var kids = [l]
		kids.append(self.parse_expr()?)
		while self.eat_op(","):
			kids.append(self.parse_expr()?)
		self.expect_op(")")?
		return ok(self.add(Node(kind: "in", flag: neg, kids: kids)))
	if self.eat_kw("BETWEEN"):
		lo := self.parse_add()?
		self.expect_kw("AND")?
		hi := self.parse_add()?
		return ok(self.add(Node(kind: "between", flag: neg, kids: [l, lo, hi])))
	return ok(l)

fn var Parser.parse_add() Int!:
	var l = self.parse_mul()?
	while self.kind() == 4 and (self.is_op("+") or self.is_op("-") or self.is_op("||")):
		t := self.text()
		self.adv()
		r := self.parse_mul()?
		l = self.add(Node(kind: "bin", op: t, kids: [l, r]))
	return ok(l)

fn var Parser.parse_mul() Int!:
	var l = self.parse_unary()?
	while self.kind() == 4 and (self.is_op("*") or self.is_op("/") or self.is_op("%")):
		t := self.text()
		self.adv()
		r := self.parse_unary()?
		l = self.add(Node(kind: "bin", op: t, kids: [l, r]))
	return ok(l)

fn var Parser.parse_unary() Int!:
	if self.eat_op("-"):
		x := self.parse_unary()?
		return ok(self.add(Node(kind: "neg", kids: [x])))
	return self.parse_primary()

fn var Parser.parse_primary() Int!:
	k := self.kind()
	if k == 2:
		n := self.num()
		self.adv()
		return ok(self.add(Node(kind: "int", i: n)))
	if k == 3:
		t := self.text()
		self.adv()
		return ok(self.add(Node(kind: "str", s: t)))
	if self.eat_kw("NULL"):
		return ok(self.add(Node(kind: "null")))
	if self.eat_op("("):
		e := self.parse_expr()?
		self.expect_op(")")?
		return ok(e)
	if k == 0:
		name := self.ident()?
		if self.eat_op("("):
			up := name.upper()
			distinct := self.eat_kw("DISTINCT")
			var kids: List[Int] = []
			var star = 0
			if self.is_op("*"):
				if up != "COUNT": return error(syn())
				self.adv()
				star = 1
			else if not self.is_op(")"):
				kids.append(self.parse_expr()?)
				while self.eat_op(","):
					kids.append(self.parse_expr()?)
			self.expect_op(")")?
			return ok(self.add(Node(kind: "func", op: up, flag: distinct, i: star, kids: kids)))
		if self.eat_op("."):
			c := self.ident()?
			return ok(self.add(Node(kind: "col", op: c, q: name, flag: true)))
		return ok(self.add(Node(kind: "col", op: name)))
	return error(syn())

fn var Parser.parse_colref() Int!:
	name := self.ident()?
	if self.eat_op("."):
		c := self.ident()?
		return ok(self.add(Node(kind: "col", op: c, q: name, flag: true)))
	return ok(self.add(Node(kind: "col", op: name)))

fn var Parser.parse_tref() Tref!:
	name := self.ident()?
	if self.eat_kw("AS"):
		a := self.ident()?
		return ok(Tref(name: name.clone(), alias: a))
	if self.kind() == 0:
		a := self.ident()?
		return ok(Tref(name: name.clone(), alias: a))
	return ok(Tref(name: name.clone(), alias: name))

fn var Parser.parse_select() Stmt!:
	var st = Stmt(kind: "select")
	self.expect_kw("SELECT")?
	st.distinct = self.eat_kw("DISTINCT")
	while true:
		if self.eat_op("*"):
			st.items.append(Item(kind: "star"))
		else if self.kind() == 0 and self.next_is_op(".") and self.toks[self.pos + 2].kind == 4 and self.toks[self.pos + 2].text == "*":
			q := self.text()
			self.adv()
			self.adv()
			self.adv()
			st.items.append(Item(kind: "tstar", q: q))
		else:
			e := self.parse_expr()?
			if self.eat_kw("AS"):
				a := self.ident()?
				st.items.append(Item(kind: "expr", expr: e, alias: a, has_alias: true))
			else:
				st.items.append(Item(kind: "expr", expr: e))
		if not self.eat_op(","): break
	if self.eat_kw("FROM"):
		st.trefs.append(self.parse_tref()?)
		while true:
			var left = false
			if self.is_kw("LEFT"):
				self.adv()
				left = true
			else if self.is_kw("INNER"):
				self.adv()
			if not self.is_kw("JOIN"):
				if left or self.pos > 0 and self.toks[self.pos - 1].kind == 1 and self.toks[self.pos - 1].text == "INNER":
					return error(syn())
				break
			self.adv()
			st.trefs.append(self.parse_tref()?)
			self.expect_kw("ON")?
			st.ons.append(self.parse_expr()?)
			st.left.append(left)
	if self.eat_kw("WHERE"):
		st.where = self.parse_expr()?
	if self.eat_kw("GROUP"):
		self.expect_kw("BY")?
		st.group.append(self.parse_colref()?)
		while self.eat_op(","):
			st.group.append(self.parse_colref()?)
	if self.eat_kw("HAVING"):
		st.having = self.parse_expr()?
	if self.eat_kw("ORDER"):
		self.expect_kw("BY")?
		while true:
			e := self.parse_expr()?
			var d = false
			if self.eat_kw("DESC"):
				d = true
			else:
				self.eat_kw("ASC")
			st.order.append(OrdItem(expr: e, desc: d))
			if not self.eat_op(","): break
	if self.eat_kw("LIMIT"):
		if self.kind() != 2: return error(syn())
		st.limit = self.num()
		self.adv()
		if self.eat_kw("OFFSET"):
			if self.kind() != 2: return error(syn())
			st.offset = self.num()
			self.adv()
	return ok(st)

fn var Parser.parse_stmt() Stmt!:
	var st = Stmt(kind: "")
	if self.is_kw("SELECT"):
		st = self.parse_select()?
	else if self.eat_kw("CREATE"):
		self.expect_kw("TABLE")?
		st.kind = "create"
		st.name = self.ident()?
		self.expect_op("(")?
		while true:
			cn := self.ident()?
			tn := self.ident()?
			up := tn.upper()
			if up != "INT" and up != "TEXT": return error(syn())
			var nn = false
			var pk = false
			while true:
				if self.eat_kw("PRIMARY"):
					self.expect_kw("KEY")?
					pk = true
				else if self.eat_kw("NOT"):
					self.expect_kw("NULL")?
					nn = true
				else:
					break
			st.coldefs.append(ColDef(name: cn, is_int: up == "INT", notnull: nn or pk, pk: pk))
			if not self.eat_op(","): break
		self.expect_op(")")?
	else if self.eat_kw("DROP"):
		self.expect_kw("TABLE")?
		st.kind = "drop"
		st.name = self.ident()?
	else if self.eat_kw("INSERT"):
		self.expect_kw("INTO")?
		st.kind = "insert"
		st.name = self.ident()?
		if self.eat_op("("):
			st.has_names = true
			st.names.append(self.ident()?)
			while self.eat_op(","):
				st.names.append(self.ident()?)
			self.expect_op(")")?
		self.expect_kw("VALUES")?
		while true:
			self.expect_op("(")?
			var row: List[Int] = []
			row.append(self.parse_expr()?)
			while self.eat_op(","):
				row.append(self.parse_expr()?)
			self.expect_op(")")?
			st.rows.append(row)
			if not self.eat_op(","): break
	else if self.eat_kw("UPDATE"):
		st.kind = "update"
		st.name = self.ident()?
		self.expect_kw("SET")?
		while true:
			st.names.append(self.ident()?)
			self.expect_op("=")?
			st.exprs.append(self.parse_expr()?)
			if not self.eat_op(","): break
		if self.eat_kw("WHERE"):
			st.where = self.parse_expr()?
	else if self.eat_kw("DELETE"):
		self.expect_kw("FROM")?
		st.kind = "delete"
		st.name = self.ident()?
		if self.eat_kw("WHERE"):
			st.where = self.parse_expr()?
	else:
		return error(syn())
	if self.kind() != 5: return error(syn())
	return ok(st)

// ---------- database ----------

type Col:
	name: String
	is_int: Bool
	notnull: Bool
	pk: Bool

type Table:
	cols: List[Col]
	rows: List[List[Val]]

type SC:
	alias: String
	name: String

fn find_col(scope: List[SC], q: String, has_q: Bool, name: String) Int!:
	var found = -1
	var count = 0
	for i in 0..scope.length():
		if scope[i].name == name and (not has_q or scope[i].alias == q):
			if found < 0: found = i
			count += 1
	if count == 0:
		if has_q: return error(fail("no such column: {q}.{name}"))
		return error(fail("no such column: {name}"))
	if count > 1: return error(fail("ambiguous column: {name}"))
	return ok(found)

fn is_agg(name: String) Bool: name == "COUNT" or name == "SUM" or name == "MIN" or name == "MAX"

fn has_agg(nodes: List[Node], n: Int) Bool:
	if nodes[n].kind == "func" and is_agg(nodes[n].op): return true
	for k in nodes[n].kids:
		if has_agg(nodes, k): return true
	return false

fn arity_error(name: String) Error: fail("wrong number of arguments to {name}")

fn resolve(nodes: List[Node], scope: List[SC], n: Int, allow_agg: Bool, in_agg: Bool, group: List[Int], need_group: Bool) Unit!:
	node := nodes[n]
	if node.kind == "col":
		idx := find_col(scope, node.q, node.flag, node.op)?
		if need_group and not in_agg and not group.contains(idx):
			return error(fail("column {node.op} must appear in GROUP BY"))
		return ok(unit)
	if node.kind == "func":
		cnt := node.kids.length()
		if is_agg(node.op):
			if not allow_agg or in_agg: return error(fail("misuse of aggregate"))
			if node.i == 0 and cnt != 1: return error(arity_error(node.op))
			for k in node.kids:
				resolve(nodes, scope, k, allow_agg, true, group, need_group)?
			return ok(unit)
		var want = -1
		if node.op == "UPPER" or node.op == "LOWER" or node.op == "LENGTH" or node.op == "ABS":
			want = 1
		else if node.op == "SUBSTR":
			want = 3
		else if node.op == "COALESCE":
			want = 0
		else:
			return error(fail("no such function: {node.op}"))
		if want > 0 and cnt != want: return error(arity_error(node.op))
		if want == 0 and cnt < 1: return error(arity_error(node.op))
		if node.flag and cnt != 1: return error(arity_error(node.op))
		for k in node.kids:
			resolve(nodes, scope, k, allow_agg, in_agg, group, need_group)?
		return ok(unit)
	for k in node.kids:
		resolve(nodes, scope, k, allow_agg, in_agg, group, need_group)?
	return ok(unit)

fn type_error() Error: fail("type error")

fn cmp_vals(a: Val, b: Val) Int:
	if a.k != b.k:
		if a.k < b.k: return -1
		return 1
	if a.k == 1 or a.k == 3:
		if a.i < b.i: return -1
		if a.i > b.i: return 1
		return 0
	if a.k == 2:
		if a.s < b.s: return -1
		if a.s > b.s: return 1
	return 0

// three-valued comparison; returns Val (null or bool)
fn compare(op: String, a: Val, b: Val) Val!:
	if a.k == 0 or b.k == 0: return ok(vnull())
	if a.k != b.k or a.k == 3: return error(type_error())
	c := cmp_vals(a, b)
	if op == "=": return ok(vbool(c == 0))
	if op == "<>": return ok(vbool(c != 0))
	if op == "<": return ok(vbool(c < 0))
	if op == "<=": return ok(vbool(c <= 0))
	if op == ">": return ok(vbool(c > 0))
	return ok(vbool(c >= 0))

fn tri_check(v: Val) Unit!:
	if v.k == 1 or v.k == 2: return error(type_error())
	return ok(unit)

fn and3(a: Val, b: Val) Val:
	if a.k == 3 and a.i == 0: return vbool(false)
	if b.k == 3 and b.i == 0: return vbool(false)
	if a.k == 0 or b.k == 0: return vnull()
	return vbool(true)

fn or3(a: Val, b: Val) Val:
	if a.k == 3 and a.i == 1: return vbool(true)
	if b.k == 3 and b.i == 1: return vbool(true)
	if a.k == 0 or b.k == 0: return vnull()
	return vbool(false)

fn not3(a: Val) Val:
	if a.k == 0: return vnull()
	return vbool(a.i == 0)

fn like_match(t: List[Int], p: List[Int]) Bool:
	// iterative wildcard matching with backtracking
	var ti = 0
	var pi = 0
	var star = -1
	var mark = 0
	while ti < t.length():
		if pi < p.length() and p[pi] == 95:
			ti += 1
			pi += 1
		else if pi < p.length() and p[pi] == 37:
			star = pi
			mark = ti
			pi += 1
		else if pi < p.length() and p[pi] == t[ti]:
			ti += 1
			pi += 1
		else if star >= 0:
			pi = star + 1
			mark += 1
			ti = mark
		else:
			return false
	while pi < p.length() and p[pi] == 37:
		pi += 1
	return pi == p.length()

fn byte_list(s: String) List[Int]:
	b := s.as_bytes()
	var out: List[Int] = []
	for i in 0..b.length():
		out.append(b.get(i).to_int())
	return out

fn ascii_upper(s: String) String:
	return s.map_chars(fn c: if c >= "a" and c <= "z": c.upper() else: c)

fn ascii_lower(s: String) String:
	return s.map_chars(fn c: if c >= "A" and c <= "Z": c.lower() else: c)

fn substr(s: String, start: Int, len: Int) String:
	b := s.as_bytes()
	n := b.length()
	if len <= 0: return ""
	var lo = start
	var hi = start + len
	if lo < 1: lo = 1
	if hi > n + 1: hi = n + 1
	if lo >= hi: return ""
	r := b.slice(lo - 1, hi - 1)
	if sl := r:
		if d := sl.decode_utf8():
			return d
	return ""

fn eval(nodes: List[Node], scope: List[SC], n: Int, row: List[Val], grp: List[List[Val]]) Val!:
	node := nodes[n]
	kind := node.kind
	if kind == "int": return ok(vint(node.i))
	if kind == "str": return ok(vtext(node.s.clone()))
	if kind == "null": return ok(vnull())
	if kind == "col":
		idx := find_col(scope, node.q, node.flag, node.op)?
		return ok(row[idx].clone())
	if kind == "neg":
		v := eval(nodes, scope, node.kids[0], row, grp)?
		if v.k == 0: return ok(vnull())
		if v.k != 1: return error(type_error())
		return ok(vint(0 - v.i))
	if kind == "bin":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		b := eval(nodes, scope, node.kids[1], row, grp)?
		if a.k == 0 or b.k == 0: return ok(vnull())
		if node.op == "||":
			if a.k != 2 or b.k != 2: return error(type_error())
			return ok(vtext(a.s + b.s))
		if a.k != 1 or b.k != 1: return error(type_error())
		if node.op == "+": return ok(vint(a.i + b.i))
		if node.op == "-": return ok(vint(a.i - b.i))
		if node.op == "*": return ok(vint(a.i * b.i))
		if b.i == 0: return error(fail("division by zero"))
		if node.op == "/": return ok(vint(a.i / b.i))
		return ok(vint(a.i % b.i))
	if kind == "cmp":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		b := eval(nodes, scope, node.kids[1], row, grp)?
		return compare(node.op, a, b)
	if kind == "and":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		if a.k == 3 and a.i == 0: return ok(vbool(false))
		tri_check(a)?
		b := eval(nodes, scope, node.kids[1], row, grp)?
		tri_check(b)?
		return ok(and3(a, b))
	if kind == "or":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		if a.k == 3 and a.i == 1: return ok(vbool(true))
		tri_check(a)?
		b := eval(nodes, scope, node.kids[1], row, grp)?
		tri_check(b)?
		return ok(or3(a, b))
	if kind == "not":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		tri_check(a)?
		return ok(not3(a))
	if kind == "isnull":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		isn := a.k == 0
		return ok(vbool(isn != node.flag))
	if kind == "like":
		a := eval(nodes, scope, node.kids[0], row, grp)?
		b := eval(nodes, scope, node.kids[1], row, grp)?
		if a.k == 0 or b.k == 0: return ok(vnull())
		if a.k != 2 or b.k != 2: return error(type_error())
		m := like_match(byte_list(a.s), byte_list(b.s))
		return ok(vbool(m != node.flag))
	if kind == "in":
		x := eval(nodes, scope, node.kids[0], row, grp)?
		var found = false
		var sawnull = false
		for j in 1..node.kids.length():
			e := eval(nodes, scope, node.kids[j], row, grp)?
			if e.k == 0:
				sawnull = true
				continue
			r := compare("=", x, e)?
			if r.k == 3 and r.i == 1: found = true
		if x.k == 0: return ok(vnull())
		if found: return ok(vbool(not node.flag))
		if sawnull: return ok(vnull())
		return ok(vbool(node.flag))
	if kind == "between":
		x := eval(nodes, scope, node.kids[0], row, grp)?
		lo := eval(nodes, scope, node.kids[1], row, grp)?
		hi := eval(nodes, scope, node.kids[2], row, grp)?
		ge := compare(">=", x, lo)?
		var res = vbool(false)
		if ge.k == 3 and ge.i == 0:
			res = vbool(false)
		else:
			le := compare("<=", x, hi)?
			res = and3(ge, le)
		if node.flag: return ok(not3(res))
		return ok(res)
	return eval_func(nodes, scope, node, row, grp)

fn eval_func(nodes: List[Node], scope: List[SC], node: Node, row: List[Val], grp: List[List[Val]]) Val!:
	name := node.op
	if is_agg(name):
		var vals: List[Val] = []
		if node.i == 1:
			return ok(vint(grp.length()))
		var seen = Set[String]()
		for r in grp:
			v := eval(nodes, scope, node.kids[0], r, [])?
			if v.k == 0: continue
			if node.flag:
				key := vkey(v)
				if seen.contains(key): continue
				seen.add(key)
			vals.append(v)
		if name == "COUNT": return ok(vint(vals.length()))
		if vals.length() == 0: return ok(vnull())
		if name == "SUM":
			var total = 0
			for v in vals:
				if v.k != 1: return error(type_error())
				total += v.i
			return ok(vint(total))
		var best = vals[0].clone()
		for v in vals:
			if v.k != best.k or v.k == 3: return error(type_error())
		for v in vals:
			c := cmp_vals(v, best)
			if name == "MIN" and c < 0: best = v.clone()
			if name == "MAX" and c > 0: best = v.clone()
		return ok(best)
	var args: List[Val] = []
	for k in node.kids:
		args.append(eval(nodes, scope, k, row, grp)?)
	if name == "COALESCE":
		for a in args:
			if a.k != 0: return ok(a.clone())
		return ok(vnull())
	for a in args:
		if a.k == 0: return ok(vnull())
	if name == "UPPER" or name == "LOWER":
		if args[0].k != 2: return error(type_error())
		if name == "UPPER": return ok(vtext(ascii_upper(args[0].s)))
		return ok(vtext(ascii_lower(args[0].s)))
	if name == "LENGTH":
		if args[0].k != 2: return error(type_error())
		return ok(vint(args[0].s.length()))
	if name == "ABS":
		if args[0].k != 1: return error(type_error())
		if args[0].i < 0: return ok(vint(0 - args[0].i))
		return ok(vint(args[0].i))
	if args[0].k != 2 or args[1].k != 1 or args[2].k != 1: return error(type_error())
	return ok(vtext(substr(args[0].s, args[1].i, args[2].i)))

fn truthy(v: Val) Bool: v.k == 3 and v.i == 1

fn cond(nodes: List[Node], scope: List[SC], n: Int, row: List[Val]) Bool!:
	v := eval(nodes, scope, n, row, [])?
	tri_check(v)?
	if v.k == 3 and v.i == 1: return ok(true)
	return ok(false)

type Db:
	tables: Map[String, Table] = Map[String, Table]()

fn scope_of(t: Table, alias: String) List[SC]:
	var out: List[SC] = []
	for c in t.cols:
		out.append(SC(alias: alias.clone(), name: c.name.clone()))
	return out

fn prefix(scope: List[SC], n: Int) List[SC]:
	var out: List[SC] = []
	for i in 0..n:
		out.append(SC(alias: scope[i].alias.clone(), name: scope[i].name.clone()))
	return out

fn check_row(cols: List[Col], row: List[Val]) Unit!:
	for i in 0..cols.length():
		v := row[i]
		if v.k == 0:
			if cols[i].notnull: return error(fail("NOT NULL constraint failed: {cols[i].name}"))
		else:
			if (cols[i].is_int and v.k != 1) or (not cols[i].is_int and v.k != 2):
				return error(fail("type mismatch in column {cols[i].name}"))
	return ok(unit)

fn pk_index(cols: List[Col]) Int:
	for i in 0..cols.length():
		if cols[i].pk: return i
	return -1

fn dup_pk(cols: List[Col], existing: List[List[Val]], added: List[List[Val]]) Unit!:
	p := pk_index(cols)
	if p < 0: return ok(unit)
	var seen = Set[String]()
	for r in existing:
		seen.add(vkey(r[p]))
	for r in added:
		k := vkey(r[p])
		if seen.contains(k): return error(fail("duplicate primary key: {show(r[p])}"))
		seen.add(k)
	return ok(unit)

fn cmp_keys(keys: List[List[Val]], descs: List[Bool], a: Int, b: Int) Int:
	for j in 0..descs.length():
		c := cmp_vals(keys[a][j], keys[b][j])
		if c != 0:
			if descs[j]: return 0 - c
			return c
	return 0

fn exec_select(db: Db, p: Parser, st: Stmt) String!:
	nodes := p.nodes
	var scope: List[SC] = []
	var tables: List[Table] = []
	var plens: List[Int] = []
	var aliases: List[String] = []
	for tr in st.trefs:
		t := db.tables.get(tr.name)
		if tt := t:
			if aliases.contains(tr.alias): return error(fail("duplicate alias: {tr.alias}"))
			aliases.append(tr.alias.clone())
			for sc in scope_of(tt, tr.alias):
				scope.append(sc)
			plens.append(scope.length())
			tables.append(tt.clone())
		else:
			return error(fail("no such table: {tr.name}"))
	var none_group: List[Int] = []
	for j in 0..st.ons.length():
		resolve(nodes, prefix(scope, plens[j + 1]), st.ons[j], false, false, none_group, false)?
	for it in st.items:
		if it.kind == "tstar" and not aliases.contains(it.q):
			return error(fail("no such table: {it.q}"))
	var gidx: List[Int] = []
	for g in st.group:
		gidx.append(find_col(scope, nodes[g].q, nodes[g].flag, nodes[g].op)?)
	if st.where >= 0:
		resolve(nodes, scope, st.where, false, false, none_group, false)?
	var aggregated = st.group.length() > 0 or st.having >= 0
	for it in st.items:
		if it.kind == "expr" and has_agg(nodes, it.expr): aggregated = true
	for o in st.order:
		if has_agg(nodes, o.expr): aggregated = true
	// output columns: name, node (-1 for column copy), col index
	var out_names: List[String] = []
	var out_nodes: List[Int] = []
	var out_cols: List[Int] = []
	for it in st.items:
		if it.kind == "expr":
			resolve(nodes, scope, it.expr, true, false, gidx, aggregated)?
			out_nodes.append(it.expr)
			out_cols.append(-1)
			if it.has_alias:
				out_names.append(it.alias.clone())
			else if nodes[it.expr].kind == "col":
				out_names.append(nodes[it.expr].op.clone())
			else:
				out_names.append("?column?")
		else:
			for ci in 0..scope.length():
				var tbl_ok = true
				if it.kind == "tstar":
					tbl_ok = scope[ci].alias == it.q
				if tbl_ok:
					if aggregated and not gidx.contains(ci):
						return error(fail("column {scope[ci].name} must appear in GROUP BY"))
					out_names.append(scope[ci].name.clone())
					out_nodes.append(-1)
					out_cols.append(ci)
	if st.having >= 0:
		resolve(nodes, scope, st.having, true, false, gidx, aggregated)?
	// order keys: >=0 output index
	var ord_out: List[Int] = []
	var ord_desc: List[Bool] = []
	for o in st.order:
		ord_desc.append(o.desc)
		on := nodes[o.expr]
		if on.kind == "int":
			if on.i < 1 or on.i > out_names.length(): return error(fail("bad ORDER BY position"))
			ord_out.append(on.i - 1)
			continue
		if on.kind == "col" and not on.flag:
			var hit = -1
			for oi in 0..out_names.length():
				if hit < 0 and out_names[oi] == on.op: hit = oi
			if hit >= 0:
				ord_out.append(hit)
				continue
		resolve(nodes, scope, o.expr, true, false, gidx, aggregated)?
		ord_out.append(-1)
	// rows
	var cur: List[List[Val]] = []
	if tables.length() == 0:
		var empty: List[Val] = []
		cur.append(empty)
	else:
		cur = tables[0].rows.clone()
		for j in 0..st.ons.length():
			sc := prefix(scope, plens[j + 1])
			inner := tables[j + 1]
			var nxt: List[List[Val]] = []
			for outer in cur:
				var matched = false
				for ir in inner.rows:
					var comb: List[Val] = []
					for v in outer:
						comb.append(v.clone())
					for v in ir:
						comb.append(v.clone())
					if cond(nodes, sc, st.ons[j], comb)?:
						matched = true
						nxt.append(comb)
				if st.left[j] and not matched:
					var comb: List[Val] = []
					for v in outer:
						comb.append(v.clone())
					for c in inner.cols:
						comb.append(vnull())
					nxt.append(comb)
			cur = nxt
	var filtered: List[List[Val]] = []
	for r in cur:
		if st.where >= 0:
			if not cond(nodes, scope, st.where, r)?: continue
		filtered.append(r.clone())
	// units
	var unit_rows: List[List[Val]] = []
	var unit_grps: List[List[List[Val]]] = []
	if not aggregated:
		for r in filtered:
			unit_rows.append(r.clone())
			unit_grps.append([])
	else:
		var groups: List[List[List[Val]]] = []
		if st.group.length() == 0:
			groups.append(filtered.clone())
		else:
			var index = Map[String, Int]()
			for r in filtered:
				var gv: List[Val] = []
				for gi in gidx:
					gv.append(r[gi].clone())
				key := rowkey(gv)
				if pos := index.get(key):
					groups[pos].append(r.clone())
				else:
					index[key] = groups.length()
					groups.append([r.clone()])
		for g in groups:
			var rep: List[Val] = []
			if g.length() > 0: rep = g[0].clone()
			if st.having >= 0:
				hv := eval(nodes, scope, st.having, rep, g)?
				tri_check(hv)?
				if not truthy(hv): continue
			unit_rows.append(rep)
			unit_grps.append(g.clone())
	// select
	var out_rows: List[List[Val]] = []
	for u in 0..unit_rows.length():
		var orow: List[Val] = []
		for oi in 0..out_names.length():
			if out_nodes[oi] >= 0:
				orow.append(eval(nodes, scope, out_nodes[oi], unit_rows[u], unit_grps[u])?)
			else:
				orow.append(unit_rows[u][out_cols[oi]].clone())
		out_rows.append(orow)
	var keep: List[Int] = []
	if st.distinct:
		var seen = Set[String]()
		for u in 0..out_rows.length():
			k := rowkey(out_rows[u])
			if seen.contains(k): continue
			seen.add(k)
			keep.append(u)
	else:
		for u in 0..out_rows.length():
			keep.append(u)
	if st.order.length() > 0:
		var keys: List[List[Val]] = []
		for u in 0..out_rows.length():
			var kv: List[Val] = []
			if keep.contains(u):
				for j in 0..st.order.length():
					if ord_out[j] >= 0:
						kv.append(out_rows[u][ord_out[j]].clone())
					else:
						kv.append(eval(nodes, scope, st.order[j].expr, unit_rows[u], unit_grps[u])?)
			keys.append(kv)
		keep = keep.sorted(fn(a: Int, b: Int) Int: cmp_keys(keys, ord_desc, a, b))
	var lines: List[String] = [out_names.join("|")]
	var skipped = 0
	var emitted = 0
	for u in keep:
		if skipped < st.offset:
			skipped += 1
			continue
		if st.limit >= 0 and emitted >= st.limit: break
		emitted += 1
		var parts: List[String] = []
		for v in out_rows[u]:
			parts.append(show(v))
		lines.append(parts.join("|"))
	lines.append("({emitted} rows)")
	return ok(lines.join("\n"))

fn exec(var db: Db, text: String) String!:
	toks := lex(text)?
	var p = Parser(toks: toks)
	st := p.parse_stmt()?
	nodes := p.nodes
	var no_group: List[Int] = []
	if st.kind == "select":
		return exec_select(db, p, st)
	if st.kind == "create":
		if db.tables.contains(st.name): return error(fail("table {st.name} already exists"))
		var cols: List[Col] = []
		var pks = 0
		for cd in st.coldefs:
			for c in cols:
				if c.name == cd.name: return error(fail("duplicate column: {cd.name}"))
			if cd.pk: pks += 1
			cols.append(Col(name: cd.name.clone(), is_int: cd.is_int, notnull: cd.notnull, pk: cd.pk))
		if pks > 1: return error(fail("multiple primary keys"))
		db.tables[st.name.clone()] = Table(cols: cols, rows: [])
		return ok("ok")
	if st.kind == "drop":
		if not db.tables.contains(st.name): return error(fail("no such table: {st.name}"))
		db.tables.remove(st.name)
		return ok("ok")
	var tbl = Table(cols: [], rows: [])
	if t := db.tables.get(st.name):
		tbl = t.clone()
	else:
		return error(fail("no such table: {st.name}"))
	scope := scope_of(tbl, st.name)
	if st.kind == "insert":
		var targets: List[Int] = []
		if st.has_names:
			for nm in st.names:
				var idx = -1
				for ci in 0..tbl.cols.length():
					if tbl.cols[ci].name == nm: idx = ci
				if idx < 0: return error(fail("no such column: {nm}"))
				if targets.contains(idx): return error(fail("duplicate column: {nm}"))
				targets.append(idx)
		else:
			for ci in 0..tbl.cols.length():
				targets.append(ci)
		var added: List[List[Val]] = []
		var empty_scope: List[SC] = []
		for r in st.rows:
			if r.length() != targets.length(): return error(fail("wrong number of values"))
			var row: List[Val] = []
			for ci in 0..tbl.cols.length():
				row.append(vnull())
			for j in 0..r.length():
				resolve(nodes, empty_scope, r[j], false, false, no_group, false)?
				row[targets[j]] = eval(nodes, empty_scope, r[j], [], [])?
			check_row(tbl.cols, row)?
			added.append(row)
		dup_pk(tbl.cols, tbl.rows, added)?
		cnt := added.length()
		for r in added:
			tbl.rows.append(r.clone())
		db.tables[st.name.clone()] = tbl
		return ok("inserted {cnt}")
	if st.kind == "update":
		var targets: List[Int] = []
		for nm in st.names:
			var idx = -1
			for ci in 0..tbl.cols.length():
				if tbl.cols[ci].name == nm: idx = ci
			if idx < 0: return error(fail("no such column: {nm}"))
			targets.append(idx)
		for e in st.exprs:
			resolve(nodes, scope, e, false, false, no_group, false)?
		if st.where >= 0:
			resolve(nodes, scope, st.where, false, false, no_group, false)?
		var newrows: List[List[Val]] = []
		var count = 0
		for r in tbl.rows:
			var hit = true
			if st.where >= 0:
				hit = cond(nodes, scope, st.where, r)?
			if hit:
				var nr: List[Val] = []
				for v in r:
					nr.append(v.clone())
				for j in 0..targets.length():
					nr[targets[j]] = eval(nodes, scope, st.exprs[j], r, [])?
				check_row(tbl.cols, nr)?
				count += 1
				newrows.append(nr)
			else:
				newrows.append(r.clone())
		var none_rows: List[List[Val]] = []
		dup_pk(tbl.cols, none_rows, newrows)?
		tbl.rows = newrows
		db.tables[st.name.clone()] = tbl
		return ok("updated {count}")
	// delete
	if st.where >= 0:
		resolve(nodes, scope, st.where, false, false, no_group, false)?
	var kept: List[List[Val]] = []
	var count = 0
	for r in tbl.rows:
		var hit = true
		if st.where >= 0:
			hit = cond(nodes, scope, st.where, r)?
		if hit:
			count += 1
		else:
			kept.append(r.clone())
	tbl.rows = kept
	db.tables[st.name.clone()] = tbl
	return ok("deleted {count}")

fn split_script(text: String) List[String]:
	cs := text.chars()
	var out: List[String] = []
	var cur = ""
	var i = 0
	n := cs.length()
	while i < n:
		c := cs[i]
		if c == "'":
			cur += c
			i += 1
			while i < n:
				cur += cs[i]
				if cs[i] == "'":
					if i + 1 < n and cs[i + 1] == "'":
						cur += "'"
						i += 2
						continue
					i += 1
					break
				i += 1
			continue
		if c == "-" and i + 1 < n and cs[i + 1] == "-":
			while i < n and cs[i] != "\n":
				cur += cs[i]
				i += 1
			continue
		if c == ";":
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += c
		i += 1
	out.append(cur)
	return out

fn blank(text: String) Bool:
	// true when only whitespace and comments
	cs := text.chars()
	var i = 0
	n := cs.length()
	while i < n:
		c := cs[i]
		if c == " " or c == "\t" or c == "\r" or c == "\n":
			i += 1
			continue
		if c == "-" and i + 1 < n and cs[i + 1] == "-":
			while i < n and cs[i] != "\n":
				i += 1
			continue
		return false
	return true

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var db = Db()
	for stmt in split_script(text):
		if blank(stmt): continue
		r := exec(var db, stmt)
		if v := r:
			print(v)
		else:
			print("error: {r.err().message}")
