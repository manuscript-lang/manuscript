import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import values from "@std/bytes.ms"

// ---------- values ----------
// tag: 0 null, 1 int, 2 text, 3 bool
type Val:
	tag: Int
	i: Int = 0
	s: String = ""

fn vnull() Val: Val(tag: 0)
fn vint(n: Int) Val: Val(tag: 1, i: n)
fn vtext(s: String) Val: Val(tag: 2, s: s)
fn vbool(b: Bool) Val: Val(tag: 3, i: if b: 1 else: 0)

fn show(v: Val) String:
	if v.tag == 0: return "NULL"
	if v.tag == 1: return "{v.i}"
	if v.tag == 2: return v.s.clone()
	if v.i == 1: return "true"
	return "false"

fn vkey(v: Val) String:
	if v.tag == 0: return "n;"
	if v.tag == 1: return "i{v.i};"
	if v.tag == 2: return "s{v.s.length()}:{v.s}"
	return "b{v.i};"

fn fail(msg: String) Val!:
	return error(Error(msg))

fn order_cmp(a: Val, b: Val) Int:
	if a.tag != b.tag: return a.tag.compare(b.tag)
	if a.tag == 1: return a.i.compare(b.i)
	if a.tag == 2: return a.s.compare(b.s)
	return a.i.compare(b.i)

// ---------- tokens ----------
// kind: 0 ident, 1 int, 2 string, 3 op, 4 eof
type Tok:
	kind: Int
	text: String = ""
	up: String = ""
	n: Int = 0

fn syntax() Error: Error("syntax error")

fn bytes_of(s: String) List[Int]:
	var out: List[Int] = []
	for b in values(s.as_bytes()):
		out.append(b.to_int())
	return out

fn sub(s: String, a: Int, b: Int) String:
	return s.slice(a, b).get("")

fn is_alpha(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

fn ascii_upper(s: String) String:
	lo := "abcdefghijklmnopqrstuvwxyz"
	up := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var out = ""
	for c in s.chars():
		if c.length() == 1:
			if idx := lo.index_of(c):
				out = out + sub(up, idx, idx + 1)
				continue
		out = out + c
	return out

fn ascii_lower(s: String) String:
	lo := "abcdefghijklmnopqrstuvwxyz"
	up := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var out = ""
	for c in s.chars():
		if c.length() == 1:
			if idx := up.index_of(c):
				out = out + sub(lo, idx, idx + 1)
				continue
		out = out + c
	return out

fn lex(src: String) List[Tok]!:
	b := bytes_of(src)
	n := b.length()
	var toks: List[Tok] = []
	var i = 0
	while i < n:
		c := b[i]
		if c == 32 or c == 9 or c == 13 or c == 10:
			i += 1
			continue
		if c == 45 and i + 1 < n and b[i + 1] == 45:
			while i < n and b[i] != 10:
				i += 1
			continue
		if is_alpha(c):
			start := i
			while i < n and (is_alpha(b[i]) or is_digit(b[i])):
				i += 1
			text := sub(src, start, i)
			toks.append(Tok(kind: 0, text: text.clone(), up: ascii_upper(text)))
			continue
		if is_digit(c):
			start := i
			while i < n and is_digit(b[i]):
				i += 1
			v := sub(src, start, i).parse_int()
			if num := v:
				toks.append(Tok(kind: 1, n: num))
			else:
				return error(syntax())
			continue
		if c == 39:
			i += 1
			var buf = ""
			var closed = false
			var seg = i
			while i < n:
				if b[i] == 39:
					if i + 1 < n and b[i + 1] == 39:
						buf = buf + sub(src, seg, i + 1)
						i += 2
						seg = i
						continue
					buf = buf + sub(src, seg, i)
					i += 1
					closed = true
					break
				i += 1
			if not closed: return error(syntax())
			toks.append(Tok(kind: 2, text: buf.clone()))
			continue
		if i + 1 < n:
			two := sub(src, i, i + 2)
			if two == "<=" or two == ">=" or two == "<>" or two == "!=" or two == "||":
				toks.append(Tok(kind: 3, text: two.clone()))
				i += 2
				continue
		one := sub(src, i, i + 1)
		if "=<>+-*/%(),.".contains(one):
			toks.append(Tok(kind: 3, text: one.clone()))
			i += 1
			continue
		return error(syntax())
	toks.append(Tok(kind: 4))
	return ok(toks)

fn split_statements(src: String) List[String]:
	b := bytes_of(src)
	n := b.length()
	var out: List[String] = []
	var start = 0
	var i = 0
	while i < n:
		c := b[i]
		if c == 39:
			i += 1
			while i < n and b[i] != 39:
				i += 1
			i += 1
			continue
		if c == 45 and i + 1 < n and b[i + 1] == 45:
			while i < n and b[i] != 10:
				i += 1
			continue
		if c == 59:
			out.append(sub(src, start, i))
			start = i + 1
		i += 1
	if start < n: out.append(sub(src, start, n))
	return out

// ---------- AST ----------
// kinds: 0 int, 1 str, 2 null, 3 col, 4 bin, 5 and, 6 or, 7 not, 8 neg, 9 isnull, 10 like, 11 in, 12 between, 13 call
type Node:
	kind: Int
	op: String = ""
	s: String = ""
	ival: Int = 0
	a: Int = -1
	b: Int = -1
	c: Int = -1
	args: List[Int] = []
	flag: Bool = false
	star: Bool = false
	distinct: Bool = false

type ColDef:
	name: String
	is_int: Bool
	pk: Bool = false
	notnull: Bool = false

type Item:
	star: Bool
	qual: String = ""
	expr: Int = -1
	alias: String = ""
	has_alias: Bool = false

type TRef:
	table: String
	alias: String

type OrderItem:
	expr: Int
	desc: Bool

type Stmt:
	kind: Int
	table: String = ""
	cols: List[ColDef] = []
	names: List[String] = []
	rows: List[List[Int]] = []
	exprs: List[Int] = []
	where_: Int = -1
	distinct: Bool = false
	items: List[Item] = []
	trefs: List[TRef] = []
	left: List[Bool] = []
	ons: List[Int] = []
	group: List[Int] = []
	having: Int = -1
	order: List[OrderItem] = []
	limit: Int = -1
	offset: Int = 0

fn is_reserved(up: String) Bool:
	words := "|SELECT|FROM|WHERE|GROUP|BY|HAVING|ORDER|LIMIT|OFFSET|JOIN|LEFT|INNER|ON|AS|AND|OR|NOT|NULL|IS|LIKE|IN|BETWEEN|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|DROP|PRIMARY|KEY|DISTINCT|ASC|DESC|"
	return words.contains("|" + up + "|")

type Parser:
	toks: List[Tok]
	pos: Int = 0
	nodes: List[Node] = []

fn Parser.kind_at(off: Int) Int:
	p := self.pos + off
	if p >= self.toks.length(): return 4
	return self.toks[p].kind

fn Parser.k() Int: self.kind_at(0)

fn Parser.is_op_at(off: Int, s: String) Bool:
	p := self.pos + off
	if p >= self.toks.length(): return false
	t := self.toks[p]
	return t.kind == 3 and t.text == s

fn Parser.is_op(s: String) Bool: self.is_op_at(0, s)

fn Parser.is_kw_at(off: Int, s: String) Bool:
	p := self.pos + off
	if p >= self.toks.length(): return false
	t := self.toks[p]
	return t.kind == 0 and t.up == s

fn Parser.is_kw(s: String) Bool: self.is_kw_at(0, s)

fn Parser.is_name_at(off: Int) Bool:
	p := self.pos + off
	if p >= self.toks.length(): return false
	t := self.toks[p]
	return t.kind == 0 and not is_reserved(t.up)

fn var Parser.adv() Void:
	self.pos += 1

fn var Parser.expect_op(s: String) Void!:
	if not self.is_op(s): return error(syntax())
	self.adv()

fn var Parser.expect_kw(s: String) Void!:
	if not self.is_kw(s): return error(syntax())
	self.adv()

fn var Parser.name() String!:
	if not self.is_name_at(0): return error(syntax())
	t := self.toks[self.pos].text.clone()
	self.adv()
	return ok(t)

fn var Parser.add(n: Node) Int:
	self.nodes.append(n)
	return self.nodes.length() - 1

fn var Parser.p_expr() Int!:
	return self.p_or()

fn var Parser.p_or() Int!:
	var l = self.p_and()?
	while self.is_kw("OR"):
		self.adv()
		r := self.p_and()?
		l = self.add(Node(kind: 6, a: l, b: r))
	return ok(l)

fn var Parser.p_and() Int!:
	var l = self.p_not()?
	while self.is_kw("AND"):
		self.adv()
		r := self.p_not()?
		l = self.add(Node(kind: 5, a: l, b: r))
	return ok(l)

fn var Parser.p_not() Int!:
	if self.is_kw("NOT"):
		self.adv()
		x := self.p_not()?
		return ok(self.add(Node(kind: 7, a: x)))
	return self.p_cmp()

fn var Parser.p_cmp() Int!:
	l := self.p_add()?
	if self.k() == 3:
		op := self.toks[self.pos].text.clone()
		if ["=", "<>", "!=", "<", "<=", ">", ">="].contains(op):
			self.adv()
			r := self.p_add()?
			o := if op == "!=": "<>" else: op
			return ok(self.add(Node(kind: 4, op: o, a: l, b: r)))
		return ok(l)
	if self.is_kw("IS"):
		self.adv()
		var neg = false
		if self.is_kw("NOT"):
			neg = true
			self.adv()
		self.expect_kw("NULL")?
		return ok(self.add(Node(kind: 9, a: l, flag: neg)))
	var neg = false
	if self.is_kw("NOT"):
		if not (self.is_kw_at(1, "LIKE") or self.is_kw_at(1, "IN") or self.is_kw_at(1, "BETWEEN")):
			return error(syntax())
		neg = true
		self.adv()
	if self.is_kw("LIKE"):
		self.adv()
		r := self.p_add()?
		return ok(self.add(Node(kind: 10, a: l, b: r, flag: neg)))
	if self.is_kw("IN"):
		self.adv()
		self.expect_op("(")?
		var args: List[Int] = []
		args.append(self.p_expr()?)
		while self.is_op(","):
			self.adv()
			args.append(self.p_expr()?)
		self.expect_op(")")?
		return ok(self.add(Node(kind: 11, a: l, args: args, flag: neg)))
	if self.is_kw("BETWEEN"):
		self.adv()
		lo := self.p_add()?
		self.expect_kw("AND")?
		hi := self.p_add()?
		return ok(self.add(Node(kind: 12, a: l, b: lo, c: hi, flag: neg)))
	return ok(l)

fn var Parser.p_add() Int!:
	var l = self.p_mul()?
	while self.is_op("+") or self.is_op("-") or self.is_op("||"):
		op := self.toks[self.pos].text.clone()
		self.adv()
		r := self.p_mul()?
		l = self.add(Node(kind: 4, op: op, a: l, b: r))
	return ok(l)

fn var Parser.p_mul() Int!:
	var l = self.p_unary()?
	while self.is_op("*") or self.is_op("/") or self.is_op("%"):
		op := self.toks[self.pos].text.clone()
		self.adv()
		r := self.p_unary()?
		l = self.add(Node(kind: 4, op: op, a: l, b: r))
	return ok(l)

fn var Parser.p_unary() Int!:
	if self.is_op("-"):
		self.adv()
		x := self.p_unary()?
		return ok(self.add(Node(kind: 8, a: x)))
	return self.p_primary()

fn var Parser.p_primary() Int!:
	k := self.k()
	if k == 1:
		n := self.toks[self.pos].n
		self.adv()
		return ok(self.add(Node(kind: 0, ival: n)))
	if k == 2:
		s := self.toks[self.pos].text.clone()
		self.adv()
		return ok(self.add(Node(kind: 1, s: s)))
	if self.is_op("("):
		self.adv()
		e := self.p_expr()?
		self.expect_op(")")?
		return ok(e)
	if self.is_kw("NULL"):
		self.adv()
		return ok(self.add(Node(kind: 2)))
	if not self.is_name_at(0): return error(syntax())
	name := self.toks[self.pos].text.clone()
	up := self.toks[self.pos].up.clone()
	self.adv()
	if self.is_op("("):
		self.adv()
		var args: List[Int] = []
		var star = false
		var distinct = false
		if self.is_op(")"):
			self.adv()
		else:
			if self.is_kw("DISTINCT"):
				distinct = true
				self.adv()
			if self.is_op("*"):
				if up != "COUNT": return error(syntax())
				star = true
				self.adv()
			else:
				args.append(self.p_expr()?)
				while self.is_op(","):
					self.adv()
					args.append(self.p_expr()?)
			self.expect_op(")")?
		return ok(self.add(Node(kind: 13, s: up, args: args, star: star, distinct: distinct)))
	if self.is_op("."):
		self.adv()
		col := self.name()?
		return ok(self.add(Node(kind: 3, s: name, op: col, flag: true)))
	return ok(self.add(Node(kind: 3, s: "", op: name, flag: false)))

fn var Parser.tref() TRef!:
	t := self.name()?
	if self.is_kw("AS"):
		self.adv()
		a := self.name()?
		return ok(TRef(table: t.clone(), alias: a))
	if self.is_name_at(0):
		a := self.name()?
		return ok(TRef(table: t.clone(), alias: a))
	return ok(TRef(table: t.clone(), alias: t))

fn var Parser.int_lit() Int!:
	if self.k() != 1: return error(syntax())
	n := self.toks[self.pos].n
	self.adv()
	return ok(n)

fn var Parser.select_stmt() Stmt!:
	var st = Stmt(kind: 6)
	self.adv()
	if self.is_kw("DISTINCT"):
		st.distinct = true
		self.adv()
	while true:
		if self.is_op("*"):
			self.adv()
			st.items.append(Item(star: true))
		else if self.is_name_at(0) and self.is_op_at(1, ".") and self.is_op_at(2, "*"):
			q := self.name()?
			self.adv()
			self.adv()
			st.items.append(Item(star: true, qual: q))
		else:
			e := self.p_expr()?
			if self.is_kw("AS"):
				self.adv()
				a := self.name()?
				st.items.append(Item(star: false, expr: e, alias: a, has_alias: true))
			else:
				st.items.append(Item(star: false, expr: e))
		if self.is_op(","):
			self.adv()
			continue
		break
	if self.is_kw("FROM"):
		self.adv()
		st.trefs.append(self.tref()?)
		while self.is_kw("JOIN") or self.is_kw("LEFT") or self.is_kw("INNER"):
			var left = false
			if self.is_kw("LEFT"):
				left = true
				self.adv()
			else if self.is_kw("INNER"):
				self.adv()
			self.expect_kw("JOIN")?
			st.trefs.append(self.tref()?)
			self.expect_kw("ON")?
			st.ons.append(self.p_expr()?)
			st.left.append(left)
	if self.is_kw("WHERE"):
		self.adv()
		st.where_ = self.p_expr()?
	if self.is_kw("GROUP"):
		self.adv()
		self.expect_kw("BY")?
		while true:
			st.group.append(self.colref()?)
			if self.is_op(","):
				self.adv()
				continue
			break
	if self.is_kw("HAVING"):
		self.adv()
		st.having = self.p_expr()?
	if self.is_kw("ORDER"):
		self.adv()
		self.expect_kw("BY")?
		while true:
			e := self.p_expr()?
			var desc = false
			if self.is_kw("ASC"):
				self.adv()
			else if self.is_kw("DESC"):
				desc = true
				self.adv()
			st.order.append(OrderItem(expr: e, desc: desc))
			if self.is_op(","):
				self.adv()
				continue
			break
	if self.is_kw("LIMIT"):
		self.adv()
		st.limit = self.int_lit()?
		if self.is_kw("OFFSET"):
			self.adv()
			st.offset = self.int_lit()?
	return ok(st)

fn var Parser.colref() Int!:
	n := self.name()?
	if self.is_op("."):
		self.adv()
		c := self.name()?
		return ok(self.add(Node(kind: 3, s: n, op: c, flag: true)))
	return ok(self.add(Node(kind: 3, s: "", op: n, flag: false)))

fn var Parser.row() List[Int]!:
	self.expect_op("(")?
	var r: List[Int] = []
	r.append(self.p_expr()?)
	while self.is_op(","):
		self.adv()
		r.append(self.p_expr()?)
	self.expect_op(")")?
	return ok(r)

fn var Parser.statement() Stmt!:
	var st = Stmt(kind: 0)
	if self.is_kw("SELECT"):
		st = self.select_stmt()?
	else if self.is_kw("CREATE"):
		self.adv()
		self.expect_kw("TABLE")?
		st.kind = 1
		st.table = self.name()?
		self.expect_op("(")?
		while true:
			cn := self.name()?
			if self.k() != 0: return error(syntax())
			ty := self.toks[self.pos].up.clone()
			if ty != "INT" and ty != "TEXT": return error(syntax())
			self.adv()
			var cd = ColDef(name: cn, is_int: ty == "INT")
			while true:
				if self.is_kw("PRIMARY"):
					self.adv()
					self.expect_kw("KEY")?
					cd.pk = true
					cd.notnull = true
				else if self.is_kw("NOT"):
					self.adv()
					self.expect_kw("NULL")?
					cd.notnull = true
				else:
					break
			st.cols.append(cd)
			if self.is_op(","):
				self.adv()
				continue
			break
		self.expect_op(")")?
	else if self.is_kw("DROP"):
		self.adv()
		self.expect_kw("TABLE")?
		st.kind = 2
		st.table = self.name()?
	else if self.is_kw("INSERT"):
		self.adv()
		self.expect_kw("INTO")?
		st.kind = 3
		st.table = self.name()?
		if self.is_op("("):
			self.adv()
			st.distinct = true
			while true:
				st.names.append(self.name()?)
				if self.is_op(","):
					self.adv()
					continue
				break
			self.expect_op(")")?
		self.expect_kw("VALUES")?
		while true:
			st.rows.append(self.row()?)
			if self.is_op(","):
				self.adv()
				continue
			break
	else if self.is_kw("UPDATE"):
		self.adv()
		st.kind = 4
		st.table = self.name()?
		self.expect_kw("SET")?
		while true:
			st.names.append(self.name()?)
			self.expect_op("=")?
			st.exprs.append(self.p_expr()?)
			if self.is_op(","):
				self.adv()
				continue
			break
		if self.is_kw("WHERE"):
			self.adv()
			st.where_ = self.p_expr()?
	else if self.is_kw("DELETE"):
		self.adv()
		self.expect_kw("FROM")?
		st.kind = 5
		st.table = self.name()?
		if self.is_kw("WHERE"):
			self.adv()
			st.where_ = self.p_expr()?
	else:
		return error(syntax())
	if self.k() != 4: return error(syntax())
	return ok(st)

// ---------- database ----------
type Table:
	name: String
	cols: List[ColDef]
	rows: List[List[Val]] = []

type Db:
	tables: List[Table] = []

fn find_table(db: Db, name: String) Int:
	for i in 0..db.tables.length():
		if db.tables[i].name == name: return i
	return -1

type ColInfo:
	alias: String
	name: String

fn is_agg_name(up: String) Bool:
	return up == "COUNT" or up == "SUM" or up == "MIN" or up == "MAX"

fn colname(n: Node) String:
	if n.flag: return "{n.s}.{n.op}"
	return n.op.clone()

fn merr(msg: String) Error: Error(msg)

fn resolve(var nodes: List[Node], id: Int, scope: List[ColInfo], agg_ok: Bool) Void!:
	n := nodes[id].clone()
	k := n.kind
	if k == 3:
		var found = -1
		var count = 0
		for i in 0..scope.length():
			ci := scope[i]
			if ci.name == n.op and (not n.flag or ci.alias == n.s):
				if found < 0: found = i
				count += 1
		if count == 0: return error(merr("no such column: {colname(n)}"))
		if count > 1: return error(merr("ambiguous column: {colname(n)}"))
		nodes[id].a = found
		return ok(unit)
	if k == 13:
		up := n.s
		argc := n.args.length()
		if is_agg_name(up):
			if not agg_ok: return error(merr("misuse of aggregate"))
			if n.star:
				// COUNT(*)
				return ok(unit)
			if argc != 1: return error(merr("wrong number of arguments to {up}"))
			for a in n.args:
				resolve(var nodes, a, scope, false)?
			return ok(unit)
		var want = -1
		if up == "UPPER" or up == "LOWER" or up == "LENGTH" or up == "ABS": want = 1
		else if up == "SUBSTR": want = 3
		else if up == "COALESCE": want = 0
		else: return error(merr("no such function: {up}"))
		if want > 0 and argc != want: return error(merr("wrong number of arguments to {up}"))
		if want == 0 and argc < 1: return error(merr("wrong number of arguments to {up}"))
		if n.distinct and argc != 1: return error(merr("wrong number of arguments to {up}"))
		for a in n.args:
			resolve(var nodes, a, scope, agg_ok)?
		return ok(unit)
	if n.a >= 0: resolve(var nodes, n.a, scope, agg_ok)?
	if n.b >= 0: resolve(var nodes, n.b, scope, agg_ok)?
	if n.c >= 0: resolve(var nodes, n.c, scope, agg_ok)?
	for a in n.args:
		resolve(var nodes, a, scope, agg_ok)?
	return ok(unit)

fn has_agg(nodes: List[Node], id: Int) Bool:
	n := nodes[id]
	if n.kind == 3: return false
	if n.kind == 13 and is_agg_name(n.s): return true
	if n.a >= 0 and has_agg(nodes, n.a): return true
	if n.b >= 0 and has_agg(nodes, n.b): return true
	if n.c >= 0 and has_agg(nodes, n.c): return true
	for a in n.args:
		if has_agg(nodes, a): return true
	return false

fn check_group(nodes: List[Node], id: Int, gcols: List[Int]) Void!:
	n := nodes[id]
	if n.kind == 3:
		if not gcols.contains(n.a): return error(merr("column {colname(n)} must appear in GROUP BY"))
		return ok(unit)
	if n.kind == 13 and is_agg_name(n.s): return ok(unit)
	if n.a >= 0: check_group(nodes, n.a, gcols)?
	if n.b >= 0: check_group(nodes, n.b, gcols)?
	if n.c >= 0: check_group(nodes, n.c, gcols)?
	for a in n.args:
		check_group(nodes, a, gcols)?
	return ok(unit)

// ---------- evaluation ----------
fn truthy(v: Val) Bool!:
	if v.tag == 3: return ok(v.i == 1)
	if v.tag == 0: return ok(false)
	return error(merr("type error"))

fn like_match(t: List[Int], p: List[Int]) Bool:
	var ti = 0
	var pi = 0
	var star = -1
	var mark = 0
	while ti < t.length():
		if pi < p.length() and p[pi] == 37:
			star = pi
			mark = ti
			pi += 1
		else if pi < p.length() and (p[pi] == 95 or p[pi] == t[ti]):
			pi += 1
			ti += 1
		else if star >= 0:
			pi = star + 1
			mark += 1
			ti = mark
		else:
			return false
	while pi < p.length() and p[pi] == 37:
		pi += 1
	return pi == p.length()

fn compare_vals(op: String, a: Val, b: Val) Val!:
	if a.tag == 0 or b.tag == 0: return ok(vnull())
	if a.tag != b.tag or a.tag == 3: return error(merr("type error"))
	c := if a.tag == 1: a.i.compare(b.i) else: a.s.compare(b.s)
	var r = false
	if op == "=": r = c == 0
	else if op == "<>": r = c != 0
	else if op == "<": r = c < 0
	else if op == "<=": r = c <= 0
	else if op == ">": r = c > 0
	else: r = c >= 0
	return ok(vbool(r))

fn and3(a: Val, b: Val) Val:
	// both already checked bool/null
	if a.tag == 3 and a.i == 0: return vbool(false)
	if b.tag == 3 and b.i == 0: return vbool(false)
	if a.tag == 0 or b.tag == 0: return vnull()
	return vbool(true)

fn or3(a: Val, b: Val) Val:
	if a.tag == 3 and a.i == 1: return vbool(true)
	if b.tag == 3 and b.i == 1: return vbool(true)
	if a.tag == 0 or b.tag == 0: return vnull()
	return vbool(false)

fn not3(a: Val) Val:
	if a.tag == 0: return vnull()
	return vbool(a.i == 0)

fn chk_bool(v: Val) Void!:
	if v.tag == 1 or v.tag == 2: return error(merr("type error"))
	return ok(unit)

fn eval(nodes: List[Node], id: Int, row: List[Val], grp: List[List[Val]], grouped: Bool) Val!:
	n := nodes[id]
	k := n.kind
	if k == 0: return ok(vint(n.ival))
	if k == 1: return ok(vtext(n.s.clone()))
	if k == 2: return ok(vnull())
	if k == 3: return ok(row[n.a].clone())
	if k == 4:
		a := eval(nodes, n.a, row, grp, grouped)?
		b := eval(nodes, n.b, row, grp, grouped)?
		op := n.op
		if op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">=":
			return compare_vals(op, a, b)
		if a.tag == 0 or b.tag == 0: return ok(vnull())
		if op == "||":
			if a.tag != 2 or b.tag != 2: return error(merr("type error"))
			return ok(vtext(a.s + b.s))
		if a.tag != 1 or b.tag != 1: return error(merr("type error"))
		if op == "+": return ok(vint(a.i + b.i))
		if op == "-": return ok(vint(a.i - b.i))
		if op == "*": return ok(vint(a.i * b.i))
		if b.i == 0: return error(merr("division by zero"))
		if op == "/": return ok(vint(a.i / b.i))
		return ok(vint(a.i % b.i))
	if k == 5:
		a := eval(nodes, n.a, row, grp, grouped)?
		chk_bool(a)?
		if a.tag == 3 and a.i == 0: return ok(vbool(false))
		b := eval(nodes, n.b, row, grp, grouped)?
		chk_bool(b)?
		return ok(and3(a, b))
	if k == 6:
		a := eval(nodes, n.a, row, grp, grouped)?
		chk_bool(a)?
		if a.tag == 3 and a.i == 1: return ok(vbool(true))
		b := eval(nodes, n.b, row, grp, grouped)?
		chk_bool(b)?
		return ok(or3(a, b))
	if k == 7:
		a := eval(nodes, n.a, row, grp, grouped)?
		chk_bool(a)?
		return ok(not3(a))
	if k == 8:
		a := eval(nodes, n.a, row, grp, grouped)?
		if a.tag == 0: return ok(vnull())
		if a.tag != 1: return error(merr("type error"))
		return ok(vint(0 - a.i))
	if k == 9:
		a := eval(nodes, n.a, row, grp, grouped)?
		isn := a.tag == 0
		return ok(vbool(if n.flag: not isn else: isn))
	if k == 10:
		a := eval(nodes, n.a, row, grp, grouped)?
		b := eval(nodes, n.b, row, grp, grouped)?
		if a.tag == 0 or b.tag == 0: return ok(vnull())
		if a.tag != 2 or b.tag != 2: return error(merr("type error"))
		m := like_match(bytes_of(a.s), bytes_of(b.s))
		return ok(vbool(if n.flag: not m else: m))
	if k == 11:
		x := eval(nodes, n.a, row, grp, grouped)?
		var found = false
		var sawnull = false
		for e in n.args:
			v := eval(nodes, e, row, grp, grouped)?
			r := compare_vals("=", x, v)?
			if r.tag == 0: sawnull = true
			else if r.i == 1: found = true
		var res = vbool(false)
		if x.tag == 0: res = vnull()
		else if found: res = vbool(true)
		else if sawnull: res = vnull()
		if n.flag: return ok(not3(res))
		return ok(res)
	if k == 12:
		x := eval(nodes, n.a, row, grp, grouped)?
		lo := eval(nodes, n.b, row, grp, grouped)?
		hi := eval(nodes, n.c, row, grp, grouped)?
		ge := compare_vals(">=", x, lo)?
		var res = vbool(false)
		if ge.tag == 3 and ge.i == 0:
			res = vbool(false)
		else:
			le := compare_vals("<=", x, hi)?
			res = and3(ge, le)
		if n.flag: return ok(not3(res))
		return ok(res)
	if is_agg_name(n.s): return eval_agg(nodes, n, grp)
	var vals: List[Val] = []
	for a in n.args:
		vals.append(eval(nodes, a, row, grp, grouped)?)
	return scalar(n.s, vals)

fn eval_agg(nodes: List[Node], n: Node, grp: List[List[Val]]) Val!:
	if n.star: return ok(vint(grp.length()))
	var vals: List[Val] = []
	var seen = Set[String]()
	empty: List[List[Val]] := []
	for r in grp:
		v := eval(nodes, n.args[0], r, empty, false)?
		if v.tag == 0: continue
		if n.distinct:
			key := vkey(v)
			if seen.contains(key): continue
			seen.add(key)
		vals.append(v)
	name := n.s
	if name == "COUNT": return ok(vint(vals.length()))
	if vals.length() == 0: return ok(vnull())
	if name == "SUM":
		var total = 0
		for v in vals:
			if v.tag != 1: return error(merr("type error"))
			total += v.i
		return ok(vint(total))
	first := vals[0].tag
	if first != 1 and first != 2: return error(merr("type error"))
	var best = vals[0].clone()
	for v in vals:
		if v.tag != first: return error(merr("type error"))
		c := order_cmp(v, best)
		if name == "MIN" and c < 0: best = v.clone()
		if name == "MAX" and c > 0: best = v.clone()
	return ok(best)

fn scalar(name: String, vals: List[Val]) Val!:
	if name == "COALESCE":
		for v in vals:
			if v.tag != 0: return ok(v.clone())
		return ok(vnull())
	for v in vals:
		if v.tag == 0: return ok(vnull())
	if name == "ABS":
		if vals[0].tag != 1: return error(merr("type error"))
		x := vals[0].i
		return ok(vint(if x < 0: 0 - x else: x))
	if name == "SUBSTR":
		if vals[0].tag != 2 or vals[1].tag != 1 or vals[2].tag != 1: return error(merr("type error"))
		s := vals[0].s
		start := vals[1].i
		len := vals[2].i
		n := s.length()
		if len <= 0 or start > n: return ok(vtext(""))
		from := if start < 1: 1 else: start
		var to = start + len - 1
		if to > n: to = n
		if to < from: return ok(vtext(""))
		return ok(vtext(sub(s, from - 1, to)))
	if vals[0].tag != 2: return error(merr("type error"))
	s := vals[0].s
	if name == "UPPER": return ok(vtext(ascii_upper(s)))
	if name == "LOWER": return ok(vtext(ascii_lower(s)))
	return ok(vint(s.length()))

// ---------- statements ----------
fn check_row(t: Table, row: List[Val]) Void!:
	for i in 0..t.cols.length():
		c := t.cols[i]
		v := row[i]
		if v.tag == 0:
			if c.notnull: return error(merr("NOT NULL constraint failed: {c.name}"))
		else:
			if (c.is_int and v.tag != 1) or (not c.is_int and v.tag != 2):
				return error(merr("type mismatch in column {c.name}"))
	return ok(unit)

fn pk_index(t: Table) Int:
	for i in 0..t.cols.length():
		if t.cols[i].pk: return i
	return -1

fn check_pk(t: Table, rows: List[List[Val]]) Void!:
	p := pk_index(t)
	if p < 0: return ok(unit)
	var seen = Set[String]()
	for r in rows:
		key := vkey(r[p])
		if seen.contains(key): return error(merr("duplicate primary key: {show(r[p])}"))
		seen.add(key)
	return ok(unit)

fn table_scope(t: Table, alias: String) List[ColInfo]:
	var sc: List[ColInfo] = []
	for c in t.cols:
		sc.append(ColInfo(alias: alias.clone(), name: c.name.clone()))
	return sc

fn clone_rows(rows: List[List[Val]]) List[List[Val]]:
	var out: List[List[Val]] = []
	for r in rows:
		out.append(r.clone())
	return out

fn exec_create(var db: Db, st: Stmt) String!:
	if find_table(db, st.table) >= 0: return error(merr("table {st.table} already exists"))
	var seen = Set[String]()
	var pks = 0
	for c in st.cols:
		if seen.contains(c.name): return error(merr("duplicate column: {c.name}"))
		seen.add(c.name.clone())
		if c.pk: pks += 1
	if pks > 1: return error(merr("multiple primary keys"))
	db.tables.append(Table(name: st.table.clone(), cols: st.cols.clone()))
	return ok("ok")

fn exec_insert(var db: Db, st: Stmt, var nodes: List[Node]) String!:
	ti := find_table(db, st.table)
	if ti < 0: return error(merr("no such table: {st.table}"))
	t := db.tables[ti]
	ncols := t.cols.length()
	var map: List[Int] = []
	if st.distinct:
		var seen = Set[String]()
		for nm in st.names:
			var idx = -1
			for i in 0..ncols:
				if t.cols[i].name == nm: idx = i
			if idx < 0: return error(merr("no such column: {nm}"))
			if seen.contains(nm): return error(merr("duplicate column: {nm}"))
			seen.add(nm.clone())
			map.append(idx)
	else:
		for i in 0..ncols:
			map.append(i)
	var newrows: List[List[Val]] = []
	empty: List[ColInfo] := []
	noeval: List[List[Val]] := []
	for r in st.rows:
		if r.length() != map.length(): return error(merr("wrong number of values"))
		var vals: List[Val] = []
		for e in r:
			resolve(var nodes, e, empty, false)?
			vals.append(eval(nodes, e, [], noeval, false)?)
		var row: List[Val] = []
		for i in 0..ncols:
			row.append(vnull())
		for j in 0..map.length():
			row[map[j]] = vals[j].clone()
		check_row(t, row)?
		newrows.append(row)
	var all = clone_rows(t.rows)
	for r in newrows:
		all.append(r.clone())
	check_pk(t, all)?
	db.tables[ti].rows = all
	return ok("inserted {newrows.length()}")

fn exec_update(var db: Db, st: Stmt, var nodes: List[Node]) String!:
	ti := find_table(db, st.table)
	if ti < 0: return error(merr("no such table: {st.table}"))
	t := db.tables[ti]
	var idxs: List[Int] = []
	for nm in st.names:
		var idx = -1
		for i in 0..t.cols.length():
			if t.cols[i].name == nm: idx = i
		if idx < 0: return error(merr("no such column: {nm}"))
		idxs.append(idx)
	scope := table_scope(t, t.name)
	for e in st.exprs:
		resolve(var nodes, e, scope, false)?
	if st.where_ >= 0: resolve(var nodes, st.where_, scope, false)?
	var out: List[List[Val]] = []
	var count = 0
	noeval: List[List[Val]] := []
	for r in t.rows:
		var hit = true
		if st.where_ >= 0:
			hit = truthy(eval(nodes, st.where_, r, noeval, false)?)?
		if not hit:
			out.append(r.clone())
			continue
		var nr = r.clone()
		for j in 0..idxs.length():
			nr[idxs[j]] = eval(nodes, st.exprs[j], r, noeval, false)?
		check_row(t, nr)?
		count += 1
		out.append(nr)
	check_pk(t, out)?
	db.tables[ti].rows = out
	return ok("updated {count}")

fn exec_delete(var db: Db, st: Stmt, var nodes: List[Node]) String!:
	ti := find_table(db, st.table)
	if ti < 0: return error(merr("no such table: {st.table}"))
	t := db.tables[ti]
	scope := table_scope(t, t.name)
	if st.where_ >= 0: resolve(var nodes, st.where_, scope, false)?
	var out: List[List[Val]] = []
	var count = 0
	noeval: List[List[Val]] := []
	for r in t.rows:
		var hit = true
		if st.where_ >= 0:
			hit = truthy(eval(nodes, st.where_, r, noeval, false)?)?
		if hit:
			count += 1
		else:
			out.append(r.clone())
	db.tables[ti].rows = out
	return ok("deleted {count}")

type OutCol:
	name: String
	node: Int

fn exec_select(db: Db, st: Stmt, var nodes: List[Node]) String!:
	// tables
	var tidx: List[Int] = []
	var aliases = Set[String]()
	for tr in st.trefs:
		ti := find_table(db, tr.table)
		if ti < 0: return error(merr("no such table: {tr.table}"))
		if aliases.contains(tr.alias): return error(merr("duplicate alias: {tr.alias}"))
		aliases.add(tr.alias.clone())
		tidx.append(ti)
	var scope: List[ColInfo] = []
	var starts: List[Int] = []
	for i in 0..st.trefs.length():
		starts.append(scope.length())
		for c in db.tables[tidx[i]].cols:
			scope.append(ColInfo(alias: st.trefs[i].alias.clone(), name: c.name.clone()))
		if i >= 1:
			resolve(var nodes, st.ons[i - 1], scope, false)?
	// stars
	for it in st.items:
		if it.star and it.qual != "":
			if not aliases.contains(it.qual): return error(merr("no such table: {it.qual}"))
	for g in st.group:
		resolve(var nodes, g, scope, false)?
	if st.where_ >= 0: resolve(var nodes, st.where_, scope, false)?
	for it in st.items:
		if not it.star: resolve(var nodes, it.expr, scope, true)?
	if st.having >= 0: resolve(var nodes, st.having, scope, true)?
	// output columns
	var outs: List[OutCol] = []
	for it in st.items:
		if it.star:
			for i in 0..scope.length():
				if it.qual == "" or scope[i].alias == it.qual:
					nid := nodes.length()
					nodes.append(Node(kind: 3, op: scope[i].name.clone(), a: i))
					outs.append(OutCol(name: scope[i].name.clone(), node: nid))
		else:
			nd := nodes[it.expr]
			var nm = "?column?"
			if it.has_alias: nm = it.alias.clone()
			else if nd.kind == 3: nm = nd.op.clone()
			outs.append(OutCol(name: nm, node: it.expr))
	// order by
	var omode: List[Int] = []
	var oval: List[Int] = []
	for oi in st.order:
		nd := nodes[oi.expr].clone()
		if nd.kind == 0:
			if nd.ival < 1 or nd.ival > outs.length(): return error(merr("bad ORDER BY position"))
			omode.append(1)
			oval.append(nd.ival - 1)
			continue
		var matched = -1
		if nd.kind == 3 and not nd.flag:
			for j in 0..outs.length():
				if outs[j].name == nd.op:
					matched = j
					break
		if matched >= 0:
			omode.append(1)
			oval.append(matched)
			continue
		resolve(var nodes, oi.expr, scope, true)?
		omode.append(2)
		oval.append(oi.expr)
	var aggregated = st.group.length() > 0 or st.having >= 0
	for o in outs:
		if has_agg(nodes, o.node): aggregated = true
	for j in 0..omode.length():
		if omode[j] == 2 and has_agg(nodes, oval[j]): aggregated = true
	var gcols: List[Int] = []
	for g in st.group:
		gcols.append(nodes[g].a)
	if aggregated:
		for o in outs:
			check_group(nodes, o.node, gcols)?
		if st.having >= 0: check_group(nodes, st.having, gcols)?
		for j in 0..omode.length():
			if omode[j] == 2: check_group(nodes, oval[j], gcols)?
	// rows
	noeval: List[List[Val]] := []
	var rows: List[List[Val]] = []
	if st.trefs.length() == 0:
		rows.append([])
	else:
		rows = clone_rows(db.tables[tidx[0]].rows)
	for i in 1..st.trefs.length():
		inner := db.tables[tidx[i]]
		width := inner.cols.length()
		var next: List[List[Val]] = []
		for r in rows:
			var matched = false
			for ir in inner.rows:
				var comb = r.clone()
				for v in ir:
					comb.append(v.clone())
				c := truthy(eval(nodes, st.ons[i - 1], comb, noeval, false)?)?
				if c:
					matched = true
					next.append(comb)
			if st.left[i - 1] and not matched:
				var comb = r.clone()
				for _w in 0..width:
					comb.append(vnull())
				next.append(comb)
		rows = next
	if st.where_ >= 0:
		var kept: List[List[Val]] = []
		for r in rows:
			if truthy(eval(nodes, st.where_, r, noeval, false)?)?:
				kept.append(r.clone())
		rows = kept
	// contexts
	var ctx_rows: List[List[Val]] = []
	var ctx_grps: List[List[List[Val]]] = []
	if aggregated:
		var gl: List[List[List[Val]]] = []
		if gcols.length() == 0:
			gl.append(clone_rows(rows))
		else:
			var index = Map[String, Int]()
			for r in rows:
				var key = ""
				for g in gcols:
					key = key + vkey(r[g])
				if gi := index.get(key):
					gl[gi].append(r.clone())
				else:
					index[key] = gl.length()
					var ng: List[List[Val]] = []
					ng.append(r.clone())
					gl.append(ng)
		for g in gl:
			var rep: List[Val] = []
			if g.length() > 0: rep = g[0].clone()
			if st.having >= 0:
				if not truthy(eval(nodes, st.having, rep, g, true)?)?: continue
			ctx_rows.append(rep)
			ctx_grps.append(clone_rows_list(g))
	else:
		ctx_rows = rows
		for _r in 0..ctx_rows.length():
			ctx_grps.append([])
	// select
	var outrows: List[List[Val]] = []
	var srcs: List[Int] = []
	var seen = Set[String]()
	for i in 0..ctx_rows.length():
		var orow: List[Val] = []
		for o in outs:
			orow.append(eval(nodes, o.node, ctx_rows[i], ctx_grps[i], aggregated)?)
		if st.distinct:
			var key = ""
			for v in orow:
				key = key + vkey(v)
			if seen.contains(key): continue
			seen.add(key)
		outrows.append(orow)
		srcs.append(i)
	// order
	var keys: List[List[Val]] = []
	for j in 0..outrows.length():
		var kr: List[Val] = []
		for m in 0..omode.length():
			if omode[m] == 1:
				kr.append(outrows[j][oval[m]].clone())
			else:
				i := srcs[j]
				kr.append(eval(nodes, oval[m], ctx_rows[i], ctx_grps[i], aggregated)?)
		keys.append(kr)
	var order: List[Int] = []
	for j in 0..outrows.length():
		order.append(j)
	if st.order.length() > 0:
		order = order.sorted(fn a, b: cmp_keys(keys[a], keys[b], st.order))
	var start = st.offset
	if start > order.length(): start = order.length()
	var stop = order.length()
	if st.limit >= 0 and start + st.limit < stop: stop = start + st.limit
	var lines: List[String] = []
	var names: List[String] = []
	for o in outs:
		names.append(o.name.clone())
	lines.append(names.join("|"))
	for p in start..stop:
		var cells: List[String] = []
		for v in outrows[order[p]]:
			cells.append(show(v))
		lines.append(cells.join("|"))
	lines.append("({stop - start} rows)")
	return ok(lines.join("\n"))

fn clone_rows_list(g: List[List[Val]]) List[List[Val]]:
	return clone_rows(g)

fn cmp_keys(a: List[Val], b: List[Val], order: List[OrderItem]) Int:
	for j in 0..a.length():
		c := order_cmp(a[j], b[j])
		if c != 0:
			return if order[j].desc: 0 - c else: c
	return 0

fn run_statement(var db: Db, text: String) String!:
	toks := lex(text)?
	if toks.length() == 1: return ok("")
	var p = Parser(toks: toks)
	st := p.statement()?
	var nodes = p.nodes.clone()
	if st.kind == 1: return exec_create(var db, st)
	if st.kind == 2:
		ti := find_table(db, st.table)
		if ti < 0: return error(merr("no such table: {st.table}"))
		db.tables.remove(ti)
		return ok("ok")
	if st.kind == 3: return exec_insert(var db, st, var nodes)
	if st.kind == 4: return exec_update(var db, st, var nodes)
	if st.kind == 5: return exec_delete(var db, st, var nodes)
	return exec_select(db, st, var nodes)

fn main() Void!:
	data := read_all(stdin(), none)?
	src := data.decode_utf8().get("")
	var db = Db()
	var out: List[String] = []
	for text in split_statements(src):
		r := run_statement(var db, text)
		if r.is_error():
			out.append("error: {r.err().message}")
		else:
			s := r.get("")
			if s != "": out.append(s)
	if out.length() > 0: print(out.join("\n"))
