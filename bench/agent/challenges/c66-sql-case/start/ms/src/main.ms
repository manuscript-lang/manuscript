import (
	Bytes from "@std/bytes.ms",
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

// ---------- values ----------
type Val {
	k Int = 0
	n Int = 0
	s String = ""
}

fn vnull() Val => Val()

fn vint(n Int) Val => Val(k: 1, n: n)

fn vtext(s String) Val => Val(k: 2, s: s)

fn vbool(b Bool) Val => Val(k: 3, n: if b { 1 } else { 0 })

fn val_str(v Val) String {
	if v.k == 0 { return "NULL" }
	if v.k == 1 { return f"{v.n}" }
	if v.k == 2 { return v.s.clone() }
	if v.n == 1 { return "true" }

	return "false"
}

fn vkey(v Val) String {
	return f"{v.k}:{v.n}:{v.s.length()}:{v.s}|"
}

fn rowkey(row List[Val], idxs List[Int]) String {
	var out = ""
	for i in idxs {
		out += vkey(row[i])
	}
	return out
}

fn err(msg String) Error => Error(msg)

fn syn() Error => Error("syntax error")

// ---------- tokens ----------
type Token {
	kind Int = 0
	text String = ""
	n Int = 0
}

type Chunk {
	toks List[Token]
	bad Bool = false
}

fn keywords() Set[String] {
	var s = Set[String]()
	words := "SELECT FROM WHERE GROUP BY HAVING ORDER LIMIT OFFSET JOIN LEFT INNER ON AS AND OR NOT NULL IS LIKE IN BETWEEN INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY DISTINCT ASC DESC".split(
		" "
	)
	for w in words {
		s.add(w.clone())
	}
	return s
}

fn is_alpha(c Int) Bool => (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c Int) Bool => c >= 48 and c <= 57

fn sub(src Bytes, a Int, b Int) String => src.decode_utf8_range(a, b) or ""

fn lex(src Bytes) List[Chunk] {
	kws := keywords()
	var out = List[Chunk]()
	var toks = List[Token]()
	var bad = false
	n := src.length()
	var i = 0

	while i < n {
		c := src.get(i).to_int()
		nx := if i + 1 < n {
			src.get(i + 1).to_int()
		} else {
			0
		}

		if c == 32 or c == 9 or c == 13 or c == 10 {
			i += 1
			continue
		}

		if c == 45 and nx == 45 {
			while i < n and src.get(i).to_int() != 10 {
				i += 1
			}
			continue
		}

		if is_alpha(c) {
			start := i
			while (
				i < n
				and (
					is_alpha(src.get(i).to_int())
					or is_digit(src.get(i).to_int())
				)
			) {
				i += 1
			}

			text := sub(src, start, i)
			up := text.upper()

			if kws.contains(up) {
				toks.append(Token(kind: 2, text: up))
			} else {
				toks.append(Token(kind: 1, text: text))
			}

			continue
		}

		if is_digit(c) {
			start := i
			while i < n and is_digit(src.get(i).to_int()) {
				i += 1
			}

			text := sub(src, start, i)
			v := text.parse_int()

			if v != null {
				toks.append(Token(kind: 3, n: v))
			} else {
				bad = true
			}

			continue
		}

		if c == 39 {
			var buf = ""
			var j = i + 1
			var closed = false
			var seg = j

			while j < n {
				if src.get(j).to_int() == 39 {
					if j + 1 < n and src.get(j + 1).to_int() == 39 {
						buf += sub(src, seg, j + 1)
						j += 2
						seg = j
						continue
					}

					buf += sub(src, seg, j)
					closed = true
					j += 1
					break
				}

				j += 1
			}

			if closed {
				toks.append(Token(kind: 4, text: buf))
				i = j
			} else {
				bad = true
				i = n
			}

			continue
		}

		if c == 59 {
			toks.append(Token(kind: 0))
			out.append(Chunk(toks: toks, bad: bad))
			toks = List[Token]()
			bad = false
			i += 1
			continue
		}

		two := (
			(c == 60 and (nx == 61 or nx == 62))
			or (c == 62 and nx == 61)
			or (c == 33 and nx == 61)
			or (c == 124 and nx == 124)
		)

		if two {
			t := sub(src, i, i + 2)
			toks.append(Token(kind: 5, text: if t == "!=" { "<>" } else { t }))
			i += 2
			continue
		}

		if (
			c == 61
			or c == 60
			or c == 62
			or c == 43
			or c == 45
			or c == 42
			or c == 47
			or c == 37
			or c == 40
			or c == 41
			or c == 44
			or c == 46
		) {
			toks.append(Token(kind: 5, text: sub(src, i, i + 1)))
			i += 1
			continue
		}

		bad = true
		i += 1
	}

	if toks.length() > 0 or bad {
		toks.append(Token(kind: 0))
		out.append(Chunk(toks: toks, bad: bad))
	}

	return out
}

// ---------- AST ----------
LIT := 0
COL := 1
NEG := 2
NOT := 3
BIN := 4
ISNULL := 5
LIKE := 6
IN := 7
BETWEEN := 8
FUNC := 9
AGG := 10

type Node {
	kind Int = 0
	op String = ""
	neg Bool = false
	lit Val = Val()
	qual String = ""
	name String = ""
	col Int = -1
	args List[Int] = List[Int]()
	star Bool = false
	distinct Bool = false
}

type Item {
	star Bool = false
	qual String = ""
	expr Int = -1
	alias String = ""
	has_alias Bool = false
}

type Tref {
	name String = ""
	alias String = ""
}

type JoinSpec {
	left Bool = false
	on Int = -1
}

type OrderSpec {
	expr Int = -1
	desc Bool = false
	ref Int = -1
}

type Stmt {
	kind Int = 0
	nodes List[Node] = List[Node]()
	table String = ""
	colnames List[String] = List[String]()
	coltypes List[Int] = List[Int]()
	colnn List[Bool] = List[Bool]()
	colpk List[Bool] = List[Bool]()
	cols List[String] = List[String]()
	hascols Bool = false
	rows List[List[Int]] = List[List[Int]]()
	setcols List[String] = List[String]()
	setexprs List[Int] = List[Int]()
	where Int = -1
	distinct Bool = false
	items List[Item] = List[Item]()
	trefs List[Tref] = List[Tref]()
	joins List[JoinSpec] = List[JoinSpec]()
	groupby List[Int] = List[Int]()
	having Int = -1
	orderby List[OrderSpec] = List[OrderSpec]()
	limit Int = -1
	offset Int = 0
}

// ---------- parser ----------
type Parser {
	toks List[Token]
	pos Int = 0
	nodes List[Node] = List[Node]()
}

fn Parser.k(off Int = 0) Int {
	var i = self.pos + off
	if i >= self.toks.length() { i = self.toks.length() - 1 }
	return self.toks[i].kind
}

fn Parser.t(off Int = 0) String {
	var i = self.pos + off
	if i >= self.toks.length() { i = self.toks.length() - 1 }
	return self.toks[i].text.clone()
}

fn Parser.num() Int => self.toks[self.pos].n

fn Parser.is_kw(w String, off Int = 0) Bool => self.k(off) == 2 and self.t(off) == w

fn Parser.is_op(o String, off Int = 0) Bool => self.k(off) == 5 and self.t(off) == o

fn var Parser.accept_kw(w String) Bool {
	if self.is_kw(w) {
		self.pos += 1
		return true
	}

	return false
}

fn var Parser.accept_op(o String) Bool {
	if self.is_op(o) {
		self.pos += 1
		return true
	}

	return false
}

fn var Parser.expect_kw(w String) Void! {
	if not self.accept_kw(
		w
	) { return error(syn()) }
}

fn var Parser.expect_op(o String) Void! {
	if not self.accept_op(o) { return error(syn()) }
}

fn var Parser.name() String! {
	if self.k() != 1 { return error(syn()) }

	s := self.t()
	self.pos += 1
	return ok(s)
}

fn var Parser.add(n Node) Int {
	id := self.nodes.length()
	self.nodes.append(n)
	return id
}

fn var Parser.bin(op String, l Int, r Int) Int {
	var a = List[Int]()
	a.append(l)
	a.append(r)
	return self.add(Node(kind: BIN, op: op, args: a))
}

fn var Parser.parse_or() Int! {
	var l = self.parse_and()?

	while self.accept_kw("OR") {
		r := self.parse_and()?
		l = self.bin("OR", l, r)
	}

	return ok(l)
}

fn var Parser.parse_and() Int! {
	var l = self.parse_not()?

	while self.accept_kw("AND") {
		r := self.parse_not()?
		l = self.bin("AND", l, r)
	}

	return ok(l)
}

fn var Parser.parse_not() Int! {
	if self.accept_kw("NOT") {
		e := self.parse_not()?
		var a = List[Int]()
		a.append(e)
		return ok(self.add(Node(kind: NOT, args: a)))
	}

	return self.parse_cmp()
}

fn var Parser.parse_cmp() Int! {
	l := self.parse_add()?

	if self.k() == 5 {
		op := self.t()

		if (
			op == "="
			or op == "<>"
			or op == "<"
			or op == "<="
			or op == ">"
			or op == ">="
		) {
			self.pos += 1

			r := self.parse_add()?
			return ok(self.bin(op, l, r))
		}

		return ok(l)
	}

	if self.accept_kw("IS") {
		neg := self.accept_kw("NOT")
		self.expect_kw("NULL")?

		var a = List[Int]()
		a.append(l)
		return ok(self.add(Node(kind: ISNULL, neg: neg, args: a)))
	}

	var neg = false

	if self.is_kw("NOT") {
		if self.is_kw("LIKE", 1) or self.is_kw("IN", 1) or self.is_kw("BETWEEN", 1) {
			self.pos += 1
			neg = true
		} else {
			return error(syn())
		}
	}

	if self.accept_kw("LIKE") {
		r := self.parse_add()?
		var a = List[Int]()
		a.append(l)
		a.append(r)
		return ok(self.add(Node(kind: LIKE, neg: neg, args: a)))
	}

	if self.accept_kw("IN") {
		self.expect_op("(")?

		var a = List[Int]()
		a.append(l)
		a.append(self.parse_or()?)
		while self.accept_op(",") {
			a.append(self.parse_or()?)
		}
		self.expect_op(")")?
		return ok(self.add(Node(kind: IN, neg: neg, args: a)))
	}

	if self.accept_kw("BETWEEN") {
		lo := self.parse_add()?
		self.expect_kw("AND")?

		hi := self.parse_add()?
		var a = List[Int]()
		a.append(l)
		a.append(lo)
		a.append(hi)
		return ok(self.add(Node(kind: BETWEEN, neg: neg, args: a)))
	}

	return ok(l)
}

fn var Parser.parse_add() Int! {
	var l = self.parse_mul()?

	while self.k() == 5 and (self.is_op("+") or self.is_op("-") or self.is_op("||")) {
		op := self.t()
		self.pos += 1

		r := self.parse_mul()?
		l = self.bin(op, l, r)
	}

	return ok(l)
}

fn var Parser.parse_mul() Int! {
	var l = self.parse_unary()?

	while self.k() == 5 and (self.is_op("*") or self.is_op("/") or self.is_op("%")) {
		op := self.t()
		self.pos += 1

		r := self.parse_unary()?
		l = self.bin(op, l, r)
	}

	return ok(l)
}

fn var Parser.parse_unary() Int! {
	if self.accept_op("-") {
		e := self.parse_unary()?
		var a = List[Int]()
		a.append(e)
		return ok(self.add(Node(kind: NEG, args: a)))
	}

	return self.parse_primary()
}

fn is_agg_name(s String) Bool => s == "COUNT" or s == "SUM" or s == "MIN" or s == "MAX"

fn var Parser.parse_primary() Int! {
	kd := self.k()

	if kd == 3 {
		v := self.num()
		self.pos += 1
		return ok(self.add(Node(kind: LIT, lit: vint(v))))
	}

	if kd == 4 {
		s := self.t()
		self.pos += 1
		return ok(self.add(Node(kind: LIT, lit: vtext(s))))
	}

	if kd == 2 {
		if self.accept_kw("NULL") { return ok(self.add(Node(kind: LIT, lit: vnull()))) }
		return error(syn())
	}

	if kd == 5 {
		if self.accept_op("(") {
			e := self.parse_or()?
			self.expect_op(")")?
			return ok(e)
		}

		return error(syn())
	}

	if kd == 1 {
		name := self.t()
		self.pos += 1

		if self.accept_op("(") {
			up := name.upper()
			var node = Node(
				kind: if is_agg_name(up) { AGG } else { FUNC },
				op: up.clone(),
			)
			if self.accept_op(")") { return ok(self.add(node)) }

			if self.accept_kw("DISTINCT") {
				node.distinct = true
			}

			if self.is_op("*") {
				if up != "COUNT" or node.distinct { return error(syn()) }

				self.pos += 1
				node.star = true
				self.expect_op(")")?
				return ok(self.add(node))
			}

			node.args.append(self.parse_or()?)
			while self.accept_op(",") {
				node.args.append(self.parse_or()?)
			}
			self.expect_op(")")?
			if node.distinct and node.args.length() != 1 { return error(syn()) }

			return ok(self.add(node))
		}

		if self.accept_op(".") {
			c := self.name()?
			return ok(self.add(Node(kind: COL, qual: name, name: c)))
		}

		return ok(self.add(Node(kind: COL, name: name)))
	}

	return error(syn())
}

fn var Parser.colref() Int! {
	n := self.name()?

	if self.accept_op(".") {
		c := self.name()?
		return ok(self.add(Node(kind: COL, qual: n, name: c)))
	}

	return ok(self.add(Node(kind: COL, name: n)))
}

fn var Parser.tref() Tref! {
	n := self.name()?
	var alias = n.clone()

	if self.accept_kw("AS") {
		alias = self.name()?
	} else if self.k() == 1 {
		alias = self.name()?
	}

	return ok(Tref(name: n, alias: alias))
}

fn var Parser.parse_select() Stmt! {
	var st = Stmt(kind: 5)
	st.distinct = self.accept_kw("DISTINCT")

	while true {
		if self.accept_op("*") {
			st.items.append(Item(star: true))
		} else if self.k() == 1 and self.is_op(".", 1) and self.is_op("*", 2) {
			q := self.t()
			self.pos += 3
			st.items.append(Item(star: true, qual: q))
		} else {
			e := self.parse_or()?

			if self.accept_kw("AS") {
				a := self.name()?
				st.items.append(Item(expr: e, alias: a, has_alias: true))
			} else {
				st.items.append(Item(expr: e))
			}
		}

		if not self.accept_op(",") { break }
	}

	if self.accept_kw("FROM") {
		st.trefs.append(self.tref()?)

		while true {
			var left = false

			if self.accept_kw("LEFT") {
				left = true
				self.expect_kw("JOIN")?
			} else if self.accept_kw("INNER") {
				self.expect_kw("JOIN")?
			} else if not self.accept_kw("JOIN") {
				break
			}

			st.trefs.append(self.tref()?)
			self.expect_kw("ON")?

			on := self.parse_or()?
			st.joins.append(JoinSpec(left: left, on: on))
		}
	}

	if self.accept_kw("WHERE") {
		st.where = self.parse_or()?
	}

	if self.accept_kw("GROUP") {
		self.expect_kw("BY")?
		st.groupby.append(self.colref()?)
		while self.accept_op(",") {
			st.groupby.append(self.colref()?)
		}
	}

	if self.accept_kw("HAVING") {
		st.having = self.parse_or()?
	}

	if self.accept_kw("ORDER") {
		self.expect_kw("BY")?

		while true {
			e := self.parse_or()?
			var desc = false

			if self.accept_kw("DESC") {
				desc = true
			} else {
				self.accept_kw("ASC")
			}

			st.orderby.append(OrderSpec(expr: e, desc: desc))
			if not self.accept_op(",") { break }
		}
	}

	if self.accept_kw("LIMIT") {
		if self.k() != 3 { return error(syn()) }

		st.limit = self.num()
		self.pos += 1

		if self.accept_kw("OFFSET") {
			if self.k() != 3 { return error(syn()) }

			st.offset = self.num()
			self.pos += 1
		}
	}

	return ok(st)
}

fn var Parser.parse_stmt() Stmt! {
	var st = Stmt()

	if self.accept_kw("SELECT") {
		st = self.parse_select()?
	} else if self.accept_kw("CREATE") {
		self.expect_kw("TABLE")?
		st.kind = 0
		st.table = self.name()?
		self.expect_op("(")?

		while true {
			cn := self.name()?
			if self.k() != 1 { return error(syn()) }

			ty := self.t().upper()
			self.pos += 1

			var tcode = 0

			if ty == "INT" {
				tcode = 1
			} else if ty == "TEXT" {
				tcode = 2
			} else {
				return error(syn())
			}

			var nn = false
			var pk = false

			while true {
				if self.accept_kw("PRIMARY") {
					self.expect_kw("KEY")?
					pk = true
					nn = true
				} else if self.accept_kw("NOT") {
					self.expect_kw("NULL")?
					nn = true
				} else {
					break
				}
			}

			st.colnames.append(cn)
			st.coltypes.append(tcode)
			st.colnn.append(nn)
			st.colpk.append(pk)
			if not self.accept_op(",") { break }
		}

		self.expect_op(")")?
	} else if self.accept_kw("DROP") {
		self.expect_kw("TABLE")?
		st.kind = 1
		st.table = self.name()?
	} else if self.accept_kw("INSERT") {
		self.expect_kw("INTO")?
		st.kind = 2
		st.table = self.name()?

		if self.accept_op("(") {
			st.hascols = true
			st.cols.append(self.name()?)
			while self.accept_op(",") {
				st.cols.append(self.name()?)
			}
			self.expect_op(")")?
		}

		self.expect_kw("VALUES")?

		while true {
			self.expect_op("(")?

			var row = List[Int]()
			row.append(self.parse_or()?)
			while self.accept_op(",") {
				row.append(self.parse_or()?)
			}
			self.expect_op(")")?
			st.rows.append(row)
			if not self.accept_op(",") { break }
		}
	} else if self.accept_kw("UPDATE") {
		st.kind = 3
		st.table = self.name()?
		self.expect_kw("SET")?

		while true {
			c := self.name()?
			self.expect_op("=")?

			e := self.parse_or()?
			st.setcols.append(c)
			st.setexprs.append(e)
			if not self.accept_op(",") { break }
		}

		if self.accept_kw("WHERE") {
			st.where = self.parse_or()?
		}
	} else if self.accept_kw("DELETE") {
		self.expect_kw("FROM")?
		st.kind = 4
		st.table = self.name()?
		if self.accept_kw("WHERE") {
			st.where = self.parse_or()?
		}
	} else {
		return error(syn())
	}

	if self.k() != 0 { return error(syn()) }

	st.nodes = self.nodes.clone()
	return ok(st)
}

// ---------- tables ----------
type Table {
	cols List[String] = List[String]()
	types List[Int] = List[Int]()
	nn List[Bool] = List[Bool]()
	pk Int = -1
	rows List[List[Val]] = List[List[Val]]()
}

fn get_table(db Map[String, Table], name String) Table! {
	t := db.get(name)
	if t != null { return ok(t.clone()) }

	return error(err(f"no such table: {name}"))
}

// ---------- resolve ----------
type ScopeCol {
	alias String
	name String
	idx Int
	tbl Int
}

type Rctx {
	cols List[ScopeCol]
	allow_agg Bool = false
	aggregated Bool = false
	gb List[Int] = List[Int]()
}

fn has_agg(nodes List[Node], id Int) Bool {
	if nodes[id].kind == AGG { return true }

	for a in nodes[id].args {
		if has_agg(nodes, a) { return true }
	}
	return false
}

fn resolve(var nodes List[Node], id Int, rc Rctx, in_agg Bool) Void! {
	kind := nodes[id].kind
	if kind == LIT { return }

	args := nodes[id].args.clone()

	if kind == COL {
		qual := nodes[id].qual.clone()
		name := nodes[id].name.clone()
		var found = -1
		var cnt = 0

		for sc in rc.cols {
			if sc.name == name and (qual == "" or sc.alias == qual) {
				cnt += 1
				found = sc.idx
			}
		}

		shown := if qual == "" { name.clone() } else { f"{qual}.{name}" }
		if cnt == 0 { return error(err(f"no such column: {shown}")) }
		if cnt > 1 { return error(err(f"ambiguous column: {name}")) }

		nodes[id].col = found
		if rc.aggregated and not in_agg and not rc.gb.contains(found) {
			return error(err(f"column {shown} must appear in GROUP BY"))
		}

		return
	}

	if kind == AGG {
		opn := nodes[id].op.clone()
		if not rc.allow_agg or in_agg { return error(err("misuse of aggregate")) }
		if not nodes[id].star and args.length() != 1 {
			return error(err(f"wrong number of arguments to {opn}"))
		}

		for a in args {
			resolve(nodes, a, rc, true)?
		}
		return
	}

	if kind == FUNC {
		opn := nodes[id].op.clone()
		n := args.length()

		if opn == "UPPER" or opn == "LOWER" or opn == "LENGTH" or opn == "ABS" {
			if n != 1 { return error(err(f"wrong number of arguments to {opn}")) }
		} else if opn == "SUBSTR" {
			if n != 3 { return error(err(f"wrong number of arguments to {opn}")) }
		} else if opn == "COALESCE" {
			if n < 1 { return error(err(f"wrong number of arguments to {opn}")) }
		} else {
			return error(err(f"no such function: {opn}"))
		}
	}

	for a in args {
		resolve(nodes, a, rc, in_agg)?
	}
}

// ---------- eval ----------
fn type_error() Error => Error("type error")

fn cmp_vals(a Val, b Val) Int! {
	if a.k == 1 and b.k == 1 {
		if a.n < b.n { return ok(-1) }
		if a.n > b.n { return ok(1) }

		return ok(0)
	}

	if a.k == 2 and b.k == 2 { return ok(a.s.compare(b.s)) }

	return error(type_error())
}

// three-valued compare: returns boolean/null Val
fn cmp_op(op String, a Val, b Val) Val! {
	if a.k == 0 or b.k == 0 { return ok(vnull()) }

	c := cmp_vals(a, b)?
	r := if op == "=" { c == 0 } else if op == "<>" { c != 0 } else if op == "<" { c < 0 } else if op == "<=" { c <= 0 } else if op == ">" { c > 0 } else { c >= 0 }
	return ok(vbool(r))
}

fn tern(v Val) Int! {
	// -1 null, 0 false, 1 true
	if v.k == 0 { return ok(-1) }
	if v.k == 3 { return ok(v.n) }

	return error(type_error())
}

fn from_tern(t Int) Val {
	if t < 0 { return vnull() }
	return vbool(t == 1)
}

fn like_match(t Bytes, p Bytes) Bool {
	tl := t.length()
	pl := p.length()
	var ti = 0
	var pi = 0
	var star = -1
	var mark = 0

	while ti < tl {
		if pi < pl and p.get(pi).to_int() == 37 {
			star = pi
			mark = ti
			pi += 1
		} else if (
			pi < pl
			and (
				p.get(pi).to_int() == 95
				or p.get(pi).to_int() == t.get(ti).to_int()
			)
		) {
			pi += 1
			ti += 1
		} else if star >= 0 {
			pi = star + 1
			mark += 1
			ti = mark
		} else {
			return false
		}
	}

	while pi < pl and p.get(pi).to_int() == 37 {
		pi += 1
	}
	return pi == pl
}

fn ascii_map(s String, up Bool) String {
	var parts = List[String]()

	for ch in s.chars() {
		if ch.length() == 1 {
			parts.append(if up { ch.upper() } else { ch.lower() })
		} else {
			parts.append(ch.clone())
		}
	}

	return parts.join("")
}

fn eval(nodes List[Node], id Int, row List[Val], grp List[List[Val]]) Val! {
	kind := nodes[id].kind
	if kind == LIT { return ok(nodes[id].lit.clone()) }
	if kind == COL { return ok(row[nodes[id].col].clone()) }

	if kind == NEG {
		v := eval(nodes, nodes[id].args[0], row, grp)?
		if v.k == 0 { return ok(vnull()) }
		if v.k != 1 { return error(type_error()) }

		return ok(vint(0 - v.n))
	}

	if kind == NOT {
		v := eval(nodes, nodes[id].args[0], row, grp)?
		t := tern(v)?
		if t < 0 { return ok(vnull()) }

		return ok(vbool(t == 0))
	}

	if kind == BIN {
		op := nodes[id].op.clone()
		l := eval(nodes, nodes[id].args[0], row, grp)?

		if op == "AND" {
			lt := tern(l)?
			if lt == 0 { return ok(vbool(false)) }

			r := eval(nodes, nodes[id].args[1], row, grp)?
			rt := tern(r)?
			if rt == 0 { return ok(vbool(false)) }
			if lt < 0 or rt < 0 { return ok(vnull()) }

			return ok(vbool(true))
		}

		if op == "OR" {
			lt := tern(l)?
			if lt == 1 { return ok(vbool(true)) }

			r := eval(nodes, nodes[id].args[1], row, grp)?
			rt := tern(r)?
			if rt == 1 { return ok(vbool(true)) }
			if lt < 0 or rt < 0 { return ok(vnull()) }

			return ok(vbool(false))
		}

		r := eval(nodes, nodes[id].args[1], row, grp)?
		if (
			op == "="
			or op == "<>"
			or op == "<"
			or op == "<="
			or op == ">"
			or op == ">="
		) {
			return cmp_op(op, l, r)
		}
		if l.k == 0 or r.k == 0 { return ok(vnull()) }

		if op == "||" {
			if l.k != 2 or r.k != 2 { return error(type_error()) }
			return ok(vtext(l.s + r.s))
		}

		if l.k != 1 or r.k != 1 { return error(type_error()) }
		if op == "+" { return ok(vint(l.n + r.n)) }
		if op == "-" { return ok(vint(l.n - r.n)) }
		if op == "*" { return ok(vint(l.n * r.n)) }
		if r.n == 0 { return error(err("division by zero")) }
		if op == "/" { return ok(vint(l.n / r.n)) }

		return ok(vint(l.n % r.n))
	}

	if kind == ISNULL {
		v := eval(nodes, nodes[id].args[0], row, grp)?
		isn := v.k == 0
		return ok(vbool(if nodes[id].neg { not isn } else { isn }))
	}

	if kind == LIKE {
		l := eval(nodes, nodes[id].args[0], row, grp)?
		r := eval(nodes, nodes[id].args[1], row, grp)?
		if l.k == 0 or r.k == 0 { return ok(vnull()) }
		if l.k != 2 or r.k != 2 { return error(type_error()) }

		m := like_match(l.s.to_bytes(), r.s.to_bytes())
		return ok(vbool(if nodes[id].neg { not m } else { m }))
	}

	if kind == IN {
		neg := nodes[id].neg
		x := eval(nodes, nodes[id].args[0], row, grp)?
		var anynull = false
		var found = false
		var i = 1

		while i < nodes[id].args.length() {
			e := eval(nodes, nodes[id].args[i], row, grp)?
			c := cmp_op("=", x, e)?

			if c.k == 0 {
				anynull = true
			} else if c.n == 1 {
				found = true
			}

			i += 1
		}

		if found { return ok(vbool(not neg)) }
		if anynull { return ok(vnull()) }

		return ok(vbool(neg))
	}

	if kind == BETWEEN {
		x := eval(nodes, nodes[id].args[0], row, grp)?
		lo := eval(nodes, nodes[id].args[1], row, grp)?
		hi := eval(nodes, nodes[id].args[2], row, grp)?
		a := cmp_op(">=", x, lo)?
		at := tern(a)?
		var res = 0

		if at == 0 {
			res = 0
		} else {
			b := cmp_op("<=", x, hi)?
			bt := tern(b)?

			if bt == 0 {
				res = 0
			} else if at < 0 or bt < 0 {
				res = -1
			} else {
				res = 1
			}
		}

		if res < 0 { return ok(vnull()) }
		if nodes[id].neg { return ok(vbool(res == 0)) }

		return ok(vbool(res == 1))
	}

	if kind == FUNC { return eval_func(nodes, id, row, grp) }

	return eval_agg(nodes, id, grp)
}

fn eval_func(nodes List[Node], id Int, row List[Val], grp List[List[Val]]) Val! {
	opn := nodes[id].op.clone()
	var vals = List[Val]()
	for a in nodes[id].args {
		vals.append(eval(nodes, a, row, grp)?)
	}

	if opn == "COALESCE" {
		for v in vals {
			if v.k != 0 { return ok(v.clone()) }
		}
		return ok(vnull())
	}

	for v in vals {
		if v.k == 0 { return ok(vnull()) }
	}

	if opn == "UPPER" or opn == "LOWER" {
		if vals[0].k != 2 { return error(type_error()) }
		return ok(vtext(ascii_map(vals[0].s, opn == "UPPER")))
	}

	if opn == "LENGTH" {
		if vals[0].k != 2 { return error(type_error()) }
		return ok(vint(vals[0].s.length()))
	}

	if opn == "ABS" {
		if vals[0].k != 1 { return error(type_error()) }
		return ok(vint(if vals[0].n < 0 { 0 - vals[0].n } else { vals[0].n }))
	}

	// SUBSTR
	if vals[0].k != 2 or vals[1].k != 1 or vals[2].k != 1 { return error(type_error()) }

	s := vals[0].s.clone()
	start := vals[1].n
	len := vals[2].n
	if len <= 0 { return ok(vtext("")) }

	lo := if start < 1 { 1 } else { start }
	e := start + len - 1
	hi := if e > s.length() { s.length() } else { e }
	if lo > hi { return ok(vtext("")) }
	if r := s.slice(lo - 1, hi) { return ok(vtext(r)) }

	return ok(vtext(""))
}

fn eval_agg(nodes List[Node], id Int, grp List[List[Val]]) Val! {
	opn := nodes[id].op.clone()
	if nodes[id].star { return ok(vint(grp.length())) }

	empty := List[List[Val]]()
	var vals = List[Val]()
	var seen = Set[String]()

	for r in grp {
		v := eval(nodes, nodes[id].args[0], r, empty)?
		if v.k == 0 { continue }

		if nodes[id].distinct {
			key := vkey(v)
			if seen.contains(key) { continue }

			seen.add(key)
		}

		vals.append(v)
	}

	if opn == "COUNT" { return ok(vint(vals.length())) }
	if vals.length() == 0 { return ok(vnull()) }

	if opn == "SUM" {
		var total = 0

		for v in vals {
			if v.k != 1 { return error(type_error()) }

			total += v.n
		}

		return ok(vint(total))
	}

	var best = vals[0].clone()
	if best.k != 1 and best.k != 2 { return error(type_error()) }

	var i = 1

	while i < vals.length() {
		c := cmp_vals(vals[i], best)?
		if (opn == "MIN" and c < 0) or (opn == "MAX" and c > 0) {
			best = vals[i].clone()
		}
		i += 1
	}

	return ok(best)
}

fn cond_true(v Val) Bool! {
	t := tern(v)?
	return ok(t == 1)
}

fn sort_cmp(a Val, b Val) Int {
	if a.k != b.k { return if a.k < b.k { - 1 } else { 1 } }

	if a.k == 1 or a.k == 3 {
		if a.n < b.n { return -1 }
		if a.n > b.n { return 1 }

		return 0
	}

	if a.k == 2 { return a.s.compare(b.s) }

	return 0
}

// ---------- select ----------
type OutRow {
	vals List[Val]
	keys List[Val]
}

fn concat(a List[Val], b List[Val]) List[Val] {
	var out = List[Val]()
	for v in a {
		out.append(v.clone())
	}
	for v in b {
		out.append(v.clone())
	}
	return out
}

fn project(
	nodes List[Node],
	outn List[Int],
	ords List[OrderSpec],
	row List[Val],
	grp List[List[Val]],
) OutRow! {
	var vals = List[Val]()
	for n in outn {
		vals.append(eval(nodes, n, row, grp)?)
	}

	var keys = List[Val]()

	for o in ords {
		if o.ref >= 0 {
			keys.append(vals[o.ref].clone())
		} else {
			keys.append(eval(nodes, o.expr, row, grp)?)
		}
	}

	return ok(OutRow(vals: vals, keys: keys))
}

fn exec_select(db Map[String, Table], var st Stmt) String! {
	var tables = List[Table]()
	var scope = List[ScopeCol]()
	var widths = List[Int]()
	var offset = 0
	var ti = 0

	for tr in st.trefs {
		t := get_table(db, tr.name)?
		for a in st.trefs.slice(0, ti).get_or([]) {
			if a.alias == tr.alias { return error(err(f"duplicate alias: {tr.alias}")) }
		}

		var ci = 0

		for c in t.cols {
			scope.append(
				ScopeCol(
					alias: tr.alias.clone(),
					name: c.clone(),
					idx: offset + ci,
					tbl: ti,
				)
			)
			ci += 1
		}

		widths.append(t.cols.length())
		offset += t.cols.length()
		tables.append(t)
		ti += 1
	}

	// aggregated?
	var aggregated = st.groupby.length() > 0 or st.having >= 0
	for it in st.items {
		if not it.star and has_agg(st.nodes, it.expr) { aggregated = true }
	}
	for o in st.orderby {
		if has_agg(st.nodes, o.expr) { aggregated = true }
	}

	// joins
	var j = 0

	for jn in st.joins {
		var sc = List[ScopeCol]()
		for c in scope {
			if c.tbl <= j + 1 {
				sc.append(
					ScopeCol(
						alias: c.alias.clone(),
						name: c.name.clone(),
						idx: c.idx,
						tbl: c.tbl,
					)
				)
			}
		}
		resolve(st.nodes, jn.on, Rctx(cols: sc), false)?
		j += 1
	}

	// stars
	var outn = List[Int]()
	var outnames = List[String]()
	var starflags = List[Bool]()

	for it in st.items {
		if it.star {
			var matched = it.qual == ""

			for c in scope {
				if it.qual == "" or c.alias == it.qual {
					matched = true
					outn.append(st.nodes.length())
					st.nodes.append(
						Node(
							kind: COL,
							qual: c.alias.clone(),
							name: c.name.clone(),
						)
					)
					outnames.append(c.name.clone())
					starflags.append(true)
				}
			}

			if not matched { return error(err(f"no such table: {it.qual}")) }
		} else {
			outn.append(it.expr)

			if it.has_alias {
				outnames.append(it.alias.clone())
			} else if st.nodes[it.expr].kind == COL {
				outnames.append(st.nodes[it.expr].name.clone())
			} else {
				outnames.append("?column?")
			}

			starflags.append(false)
		}
	}

	// group by
	var gb = List[Int]()

	for g in st.groupby {
		resolve(st.nodes, g, Rctx(cols: scope.clone()), false)?
		gb.append(st.nodes[g].col)
	}

	// where
	if st.where >= 0 {
		resolve(st.nodes, st.where, Rctx(cols: scope.clone()), false)?
	}

	rc := Rctx(
		cols: scope.clone(),
		allow_agg: true,
		aggregated: aggregated,
		gb: gb.clone(),
	)
	for n in outn {
		resolve(st.nodes, n, rc, false)?
	}
	if st.having >= 0 {
		resolve(st.nodes, st.having, rc, false)?
	}

	var ords = List[OrderSpec]()

	for o0 in st.orderby {
		var o = OrderSpec(expr: o0.expr, desc: o0.desc)
		nd := st.nodes[o.expr].clone()

		if nd.kind == LIT and nd.lit.k == 1 {
			if nd.lit.n < 1 or nd.lit.n > outn.length() {
				return error(err("bad ORDER BY position"))
			}

			o.ref = nd.lit.n - 1
		} else {
			if nd.kind == COL and nd.qual == "" {
				var oi = 0

				for nm in outnames {
					if nm == nd.name and o.ref < 0 { o.ref = oi }
					oi += 1
				}
			}

			if o.ref < 0 {
				resolve(st.nodes, o.expr, rc, false)?
			}
		}

		ords.append(o)
	}

	// rows
	var rows = List[List[Val]]()

	if st.trefs.length() == 0 {
		rows.append(List[Val]())
	} else {
		for r in tables[0].rows {
			rows.append(r.clone())
		}

		var k = 0

		for jn in st.joins {
			var nulls = List[Val]()
			for _x in 0..widths[k + 1] {
				nulls.append(vnull())
			}

			var next = List[List[Val]]()

			for r in rows {
				var matched = false

				for r2 in tables[k + 1].rows {
					c := concat(r, r2)
					v := eval(st.nodes, jn.on, c, List[List[Val]]())?

					if cond_true(v)? {
						matched = true
						next.append(c)
					}
				}

				if jn.left and not matched {
					next.append(concat(r, nulls))
				}
			}

			rows = next
			k += 1
		}
	}

	if st.where >= 0 {
		var kept = List[List[Val]]()

		for r in rows {
			v := eval(st.nodes, st.where, r, List[List[Val]]())?
			if cond_true(v)? { kept.append(r.clone()) }
		}

		rows = kept
	}

	var outrows = List[OutRow]()
	empty := List[List[Val]]()

	if aggregated {
		var groups = List[List[List[Val]]]()

		if gb.length() > 0 {
			var index = Map[String, Int]()

			for r in rows {
				key := rowkey(r, gb)
				gi := index.get(key)

				if gi != null {
					groups[gi].append(r.clone())
				} else {
					index[key] = groups.length()

					var g = List[List[Val]]()
					g.append(r.clone())
					groups.append(g)
				}
			}
		} else {
			groups.append(rows.clone())
		}

		for g in groups {
			first := if g.length() > 0 { g[0].clone() } else { List[Val]() }

			if st.having >= 0 {
				hv := eval(st.nodes, st.having, first, g)?
				if not cond_true(hv)? { continue }
			}

			outrows.append(project(st.nodes, outn, ords, first, g)?)
		}
	} else {
		for r in rows {
			outrows.append(project(st.nodes, outn, ords, r, empty)?)
		}
	}

	if st.distinct {
		var seen = Set[String]()
		var uniq = List[OutRow]()
		var allidx = List[Int]()
		for q in 0..outn.length() {
			allidx.append(q)
		}

		for o in outrows {
			key := rowkey(o.vals, allidx)
			if seen.contains(key) { continue }

			seen.add(key)
			uniq.append(OutRow(vals: o.vals.clone(), keys: o.keys.clone()))
		}

		outrows = uniq
	}

	if ords.length() > 0 {
		outrows.sort((a, b) => order_cmp(a, b, ords))
	}

	var lines = List[String]()
	lines.append(outnames.join("|"))

	var skipped = 0
	var count = 0

	for o in outrows {
		if skipped < st.offset {
			skipped += 1
			continue
		}

		if st.limit >= 0 and count >= st.limit { break }

		count += 1

		var cells = List[String]()
		for v in o.vals {
			cells.append(val_str(v))
		}
		lines.append(cells.join("|"))
	}

	lines.append(f"({count} rows)")
	return ok(lines.join("\n"))
}

fn order_cmp(a OutRow, b OutRow, ords List[OrderSpec]) Int {
	var i = 0

	while i < ords.length() {
		c := sort_cmp(a.keys[i], b.keys[i])
		if c != 0 { return if ords[i].desc { 0 - c } else { c } }

		i += 1
	}

	return 0
}

// ---------- DML ----------
fn check_row(t Table, row List[Val]) Void! {
	var i = 0

	while i < t.cols.length() {
		v := row[i]

		if v.k == 0 {
			if t.nn[i] { return error(err(f"NOT NULL constraint failed: {t.cols[i]}")) }
		} else if v.k != t.types[i] {
			return error(err(f"type mismatch in column {t.cols[i]}"))
		}

		i += 1
	}
}

fn check_pk(t Table, rows List[List[Val]]) Void! {
	if t.pk < 0 { return }

	var seen = Set[String]()

	for r in rows {
		key := vkey(r[t.pk])
		if seen.contains(
			key
		) { return error(err(f"duplicate primary key: {val_str(r[t.pk])}")) }

		seen.add(key)
	}
}

fn table_scope(name String, t Table) List[ScopeCol] {
	var sc = List[ScopeCol]()
	var i = 0

	for c in t.cols {
		sc.append(ScopeCol(alias: name.clone(), name: c.clone(), idx: i, tbl: 0))
		i += 1
	}

	return sc
}

fn col_index(t Table, name String) Int {
	var i = 0

	for c in t.cols {
		if c == name { return i }

		i += 1
	}

	return -1
}

fn exec_insert(var db Map[String, Table], var st Stmt) String! {
	t := get_table(db, st.table)?
	var colmap = List[Int]()

	if st.hascols {
		for c in st.cols {
			i := col_index(t, c)
			if i < 0 { return error(err(f"no such column: {c}")) }
			if colmap.contains(
				i
			) { return error(err(f"duplicate column: {c}")) }

			colmap.append(i)
		}
	} else {
		for i in 0..t.cols.length() {
			colmap.append(i)
		}
	}

	rc := Rctx(cols: List[ScopeCol](), allow_agg: false)
	var newrows = List[List[Val]]()
	empty := List[List[Val]]()

	for r in st.rows {
		if r.length() != colmap.length() { return error(err("wrong number of values")) }

		var row = List[Val]()
		for _x in 0..t.cols.length() {
			row.append(vnull())
		}

		var k = 0

		for e in r {
			resolve(st.nodes, e, rc, false)?

			v := eval(st.nodes, e, List[Val](), empty)?
			row[colmap[k]] = v
			k += 1
		}

		check_row(t, row)?
		newrows.append(row)
	}

	var all = List[List[Val]]()
	for r in t.rows {
		all.append(r.clone())
	}
	for r in newrows {
		all.append(r.clone())
	}
	check_pk(t, all)?

	n := newrows.length()
	var nt = t.clone()
	nt.rows = all
	db[st.table.clone()] = nt
	return ok(f"inserted {n}")
}

fn exec_update(var db Map[String, Table], var st Stmt) String! {
	t := get_table(db, st.table)?
	var idxs = List[Int]()

	for c in st.setcols {
		i := col_index(t, c)
		if i < 0 { return error(err(f"no such column: {c}")) }

		idxs.append(i)
	}

	rc := Rctx(cols: table_scope(st.table, t), allow_agg: false)
	for e in st.setexprs {
		resolve(st.nodes, e, rc, false)?
	}
	if st.where >= 0 {
		resolve(st.nodes, st.where, rc, false)?
	}

	empty := List[List[Val]]()
	var newrows = List[List[Val]]()
	var count = 0

	for r in t.rows {
		var hit = true

		if st.where >= 0 {
			v := eval(st.nodes, st.where, r, empty)?
			hit = cond_true(v)?
		}

		if hit {
			count += 1

			var nr = r.clone()
			var k = 0

			for e in st.setexprs {
				nr[idxs[k]] = eval(st.nodes, e, r, empty)?
				k += 1
			}

			check_row(t, nr)?
			newrows.append(nr)
		} else {
			newrows.append(r.clone())
		}
	}

	check_pk(t, newrows)?

	var nt = t.clone()
	nt.rows = newrows
	db[st.table.clone()] = nt
	return ok(f"updated {count}")
}

fn exec_delete(var db Map[String, Table], var st Stmt) String! {
	t := get_table(db, st.table)?
	rc := Rctx(cols: table_scope(st.table, t), allow_agg: false)
	if st.where >= 0 {
		resolve(st.nodes, st.where, rc, false)?
	}

	empty := List[List[Val]]()
	var newrows = List[List[Val]]()
	var count = 0

	for r in t.rows {
		var hit = true

		if st.where >= 0 {
			v := eval(st.nodes, st.where, r, empty)?
			hit = cond_true(v)?
		}

		if hit {
			count += 1
		} else {
			newrows.append(r.clone())
		}
	}

	var nt = t.clone()
	nt.rows = newrows
	db[st.table.clone()] = nt
	return ok(f"deleted {count}")
}

fn exec_create(var db Map[String, Table], st Stmt) String! {
	if db.contains(
		st.table
	) { return error(err(f"table {st.table} already exists")) }

	var t = Table()
	var i = 0

	for c in st.colnames {
		if t.cols.contains(
			c
		) { return error(err(f"duplicate column: {c}")) }

		t.cols.append(c.clone())
		t.types.append(st.coltypes[i])
		t.nn.append(st.colnn[i])

		if st.colpk[i] {
			if t.pk >= 0 { return error(err("multiple primary keys")) }

			t.pk = i
		}

		i += 1
	}

	db[st.table.clone()] = t
	return ok("ok")
}

fn exec_drop(var db Map[String, Table], st Stmt) String! {
	if not db.contains(
		st.table
	) { return error(err(f"no such table: {st.table}")) }

	db.remove(st.table)
	return ok("ok")
}

fn run_chunk(var db Map[String, Table], ch Chunk) String! {
	if ch.bad { return error(syn()) }

	var p = Parser(toks: ch.toks.clone())
	var st = p.parse_stmt()?
	if st.kind == 0 { return exec_create(db, st) }
	if st.kind == 1 { return exec_drop(db, st) }
	if st.kind == 2 { return exec_insert(db, st) }
	if st.kind == 3 { return exec_update(db, st) }
	if st.kind == 4 { return exec_delete(db, st) }

	return exec_select(db, st)
}

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Void! {
	data := read_all(stdin())?
	chunks := lex(data)
	var db = Map[String, Table]()

	for ch in chunks {
		if not ch.bad and ch.toks.length() == 1 { continue }

		r := run_chunk(db, ch)

		if s := r {
			print(s)
		} else {
			print(f"error: {r.err().message}")
		}
	}
}
