import Bytes from "@std/bytes.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

enum Val:
	Null
	I(n: Int)
	T(s: String)
	B(b: Bool)

enum Ex:
	Lit(v: Val)
	Col(q: String, name: String)
	Ref(i: Int, name: String)
	Neg(e: Ex)
	Arith(op: String, l: Ex, r: Ex)
	Cmp(op: String, l: Ex, r: Ex)
	And(l: Ex, r: Ex)
	Or(l: Ex, r: Ex)
	Not(e: Ex)
	IsNull(e: Ex, neg: Bool)
	Like(e: Ex, p: Ex, neg: Bool)
	In(e: Ex, xs: List[Ex], neg: Bool)
	Between(e: Ex, lo: Ex, hi: Ex, neg: Bool)
	Call(name: String, args: List[Ex], distinct: Bool, star: Bool)

type Tok:
	kind: Int
	text: String
	num: Int = 0

type ColDef:
	name: String
	is_int: Bool
	notnull: Bool
	pk: Bool

type SetItem:
	name: String
	e: Ex

type Item:
	kind: Int
	e: Ex
	alias: String
	has_alias: Bool
	tname: String

type TRef:
	name: String
	alias: String

type OrderItem:
	e: Ex
	desc: Bool

type Query:
	distinct: Bool
	items: List[Item]
	refs: List[TRef]
	jleft: List[Bool]
	jon: List[Ex]
	has_where: Bool
	where_: Ex
	group_by: List[Ex]
	has_having: Bool
	having: Ex
	order: List[OrderItem]
	limit: Int
	offset: Int

enum Stmt:
	Create(name: String, cols: List[ColDef])
	Drop(name: String)
	Insert(table: String, cols: List[String], has_cols: Bool, rows: List[List[Ex]])
	Update(table: String, sets: List[SetItem], has_where: Bool, where_: Ex)
	Delete(table: String, has_where: Bool, where_: Ex)
	Select(q: Query)

type Table:
	name: String
	cols: List[ColDef]
	rows: List[List[Val]]

type Db:
	tables: List[Table]

type ColInfo:
	alias: String
	name: String

type RRow:
	out: List[Val]
	keys: List[Val]
	src: Int

type OrdSpec:
	pos: Int
	e: Ex
	desc: Bool

fn fail(msg: String) Error:
	return Error(msg)

fn nul() Ex:
	return Ex.Lit(Val.Null)

// ---------- lexer ----------

fn is_alpha(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

fn is_keyword(s: String) Bool:
	kws := ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"]
	for k in kws:
		if k == s: return true
	return false

fn lex(src: String) List[Tok]!:
	b := src.as_bytes()
	n := b.length()
	var toks = List[Tok]()
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
			st := i
			while i < n and (is_alpha(b.get(i).to_int()) or is_digit(b.get(i).to_int())):
				i += 1
			word := b.decode_utf8_range(st, i).get("")
			up := word.upper()
			if is_keyword(up):
				toks.append(Tok(1, up))
			else:
				toks.append(Tok(0, word))
			continue
		if is_digit(c):
			st := i
			while i < n and is_digit(b.get(i).to_int()):
				i += 1
			word := b.decode_utf8_range(st, i).get("")
			if v := word.parse_int():
				toks.append(Tok(2, word, v))
			else:
				return error(fail("syntax error"))
			continue
		if c == 39:
			i += 1
			var done = false
			var st = i
			var acc = ""
			while i < n:
				if b.get(i).to_int() == 39:
					if i + 1 < n and b.get(i + 1).to_int() == 39:
						acc = acc + b.decode_utf8_range(st, i + 1).get("")
						i += 2
						st = i
						continue
					acc = acc + b.decode_utf8_range(st, i).get("")
					i += 1
					done = true
					break
				i += 1
			if not done:
				return error(fail("syntax error"))
			toks.append(Tok(3, acc))
			continue
		if i + 1 < n:
			two := b.decode_utf8_range(i, i + 2).get("")
			if two == "<=" or two == ">=" or two == "<>" or two == "!=" or two == "||":
				toks.append(Tok(4, two))
				i += 2
				continue
		one := b.decode_utf8_range(i, i + 1).get("")
		if one == "=" or one == "<" or one == ">" or one == "+" or one == "-" or one == "*" or one == "/" or one == "%" or one == "(" or one == ")" or one == "," or one == ".":
			toks.append(Tok(4, one))
			i += 1
			continue
		return error(fail("syntax error"))
	return ok(toks)

fn split_script(src: String) List[String]:
	b := src.as_bytes()
	n := b.length()
	var res = List[String]()
	var st = 0
	var i = 0
	var in_str = false
	var in_com = false
	while i < n:
		c := b.get(i).to_int()
		if in_com:
			if c == 10: in_com = false
		else if in_str:
			if c == 39: in_str = false
		else:
			if c == 39:
				in_str = true
			else if c == 45 and i + 1 < n and b.get(i + 1).to_int() == 45:
				in_com = true
			else if c == 59:
				res.append(b.decode_utf8_range(st, i).get(""))
				st = i + 1
		i += 1
	res.append(b.decode_utf8_range(st, n).get(""))
	return res

// ---------- parser ----------

type P:
	toks: List[Tok]
	pos: Int = 0

fn syn() Error:
	return Error("syntax error")

fn P.kind_at(k: Int) Int:
	j := self.pos + k
	if j >= self.toks.length(): return -1
	return self.toks[j].kind

fn P.text_at(k: Int) String:
	j := self.pos + k
	if j >= self.toks.length(): return ""
	return self.toks[j].text.clone()

fn P.num_at(k: Int) Int:
	j := self.pos + k
	if j >= self.toks.length(): return 0
	return self.toks[j].num

fn P.at_end() Bool:
	return self.pos >= self.toks.length()

fn P.is_kw(k: String) Bool:
	return self.kind_at(0) == 1 and self.text_at(0) == k

fn P.is_op(o: String) Bool:
	return self.kind_at(0) == 4 and self.text_at(0) == o

fn var P.eat_kw(k: String) Bool:
	if self.is_kw(k):
		self.pos += 1
		return true
	return false

fn var P.eat_op(o: String) Bool:
	if self.is_op(o):
		self.pos += 1
		return true
	return false

fn var P.expect_kw(k: String) Unit!:
	if not self.eat_kw(k): return error(syn())
	return ok(unit)

fn var P.expect_op(o: String) Unit!:
	if not self.eat_op(o): return error(syn())
	return ok(unit)

fn var P.name() String!:
	if self.kind_at(0) != 0: return error(syn())
	s := self.text_at(0)
	self.pos += 1
	return ok(s)

fn var P.parse_or() Ex!:
	var l = self.parse_and()?
	while self.eat_kw("OR"):
		r := self.parse_and()?
		l = Ex.Or(l, r)
	return ok(l)

fn var P.parse_and() Ex!:
	var l = self.parse_not()?
	while self.eat_kw("AND"):
		r := self.parse_not()?
		l = Ex.And(l, r)
	return ok(l)

fn var P.parse_not() Ex!:
	if self.eat_kw("NOT"):
		e := self.parse_not()?
		return ok(Ex.Not(e))
	return self.parse_cmp()

fn var P.parse_cmp() Ex!:
	l := self.parse_add()?
	if self.kind_at(0) == 4:
		op := self.text_at(0)
		if op == "=" or op == "<>" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=":
			self.pos += 1
			r := self.parse_add()?
			o := if op == "!=": "<>" else: op
			return ok(Ex.Cmp(o, l, r))
	if self.eat_kw("IS"):
		neg := self.eat_kw("NOT")
		self.expect_kw("NULL")?
		return ok(Ex.IsNull(l, neg))
	var neg = false
	if self.is_kw("NOT"):
		self.pos += 1
		neg = true
		if not (self.is_kw("LIKE") or self.is_kw("IN") or self.is_kw("BETWEEN")):
			return error(syn())
	if self.eat_kw("LIKE"):
		p := self.parse_add()?
		return ok(Ex.Like(l, p, neg))
	if self.eat_kw("IN"):
		self.expect_op("(")?
		var xs = List[Ex]()
		xs.append(self.parse_or()?)
		while self.eat_op(","):
			xs.append(self.parse_or()?)
		self.expect_op(")")?
		return ok(Ex.In(l, xs, neg))
	if self.eat_kw("BETWEEN"):
		lo := self.parse_add()?
		self.expect_kw("AND")?
		hi := self.parse_add()?
		return ok(Ex.Between(l, lo, hi, neg))
	return ok(l)

fn var P.parse_add() Ex!:
	var l = self.parse_mul()?
	while self.is_op("+") or self.is_op("-") or self.is_op("||"):
		op := self.text_at(0)
		self.pos += 1
		r := self.parse_mul()?
		l = Ex.Arith(op, l, r)
	return ok(l)

fn var P.parse_mul() Ex!:
	var l = self.parse_unary()?
	while self.is_op("*") or self.is_op("/") or self.is_op("%"):
		op := self.text_at(0)
		self.pos += 1
		r := self.parse_unary()?
		l = Ex.Arith(op, l, r)
	return ok(l)

fn var P.parse_unary() Ex!:
	if self.eat_op("-"):
		e := self.parse_unary()?
		return ok(Ex.Neg(e))
	return self.parse_primary()

fn var P.parse_primary() Ex!:
	k := self.kind_at(0)
	if k == 2:
		v := self.num_at(0)
		self.pos += 1
		return ok(Ex.Lit(Val.I(v)))
	if k == 3:
		s := self.text_at(0)
		self.pos += 1
		return ok(Ex.Lit(Val.T(s)))
	if self.eat_kw("NULL"):
		return ok(nul())
	if self.eat_op("("):
		e := self.parse_or()?
		self.expect_op(")")?
		return ok(e)
	if k == 0:
		name := self.text_at(0)
		if self.kind_at(1) == 4 and self.text_at(1) == "(":
			self.pos += 2
			up := name.upper()
			var distinct = false
			var star = false
			var args = List[Ex]()
			if self.eat_kw("DISTINCT"): distinct = true
			if self.eat_op(")"):
				return ok(Ex.Call(up, args, distinct, false))
			if self.is_op("*"):
				if up != "COUNT": return error(syn())
				self.pos += 1
				star = true
				self.expect_op(")")?
				return ok(Ex.Call(up, args, distinct, true))
			args.append(self.parse_or()?)
			while self.eat_op(","):
				args.append(self.parse_or()?)
			self.expect_op(")")?
			return ok(Ex.Call(up, args, distinct, star))
		if self.kind_at(1) == 4 and self.text_at(1) == ".":
			self.pos += 2
			n2 := self.name()?
			return ok(Ex.Col(name, n2))
		self.pos += 1
		return ok(Ex.Col("", name))
	return error(syn())

fn var P.parse_colref() Ex!:
	n := self.name()?
	if self.eat_op("."):
		n2 := self.name()?
		return ok(Ex.Col(n, n2))
	return ok(Ex.Col("", n))

fn var P.parse_tref() TRef!:
	n := self.name()?
	var alias = n.clone()
	if self.eat_kw("AS"):
		alias = self.name()?
	else if self.kind_at(0) == 0:
		alias = self.name()?
	return ok(TRef(n, alias))

fn var P.parse_select() Stmt!:
	distinct := self.eat_kw("DISTINCT")
	var items = List[Item]()
	while true:
		if self.eat_op("*"):
			items.append(Item(1, nul(), "", false, ""))
		else if self.kind_at(0) == 0 and self.kind_at(1) == 4 and self.text_at(1) == "." and self.kind_at(2) == 4 and self.text_at(2) == "*":
			tn := self.text_at(0)
			self.pos += 3
			items.append(Item(2, nul(), "", false, tn))
		else:
			e := self.parse_or()?
			if self.eat_kw("AS"):
				a := self.name()?
				items.append(Item(0, e, a, true, ""))
			else:
				items.append(Item(0, e, "", false, ""))
		if not self.eat_op(","): break
	var refs = List[TRef]()
	var jleft = List[Bool]()
	var jon = List[Ex]()
	if self.eat_kw("FROM"):
		refs.append(self.parse_tref()?)
		while true:
			var left = false
			if self.is_kw("INNER"):
				self.pos += 1
				self.expect_kw("JOIN")?
			else if self.is_kw("LEFT"):
				self.pos += 1
				left = true
				self.expect_kw("JOIN")?
			else if self.is_kw("JOIN"):
				self.pos += 1
			else:
				break
			refs.append(self.parse_tref()?)
			self.expect_kw("ON")?
			jon.append(self.parse_or()?)
			jleft.append(left)
	var has_where = false
	var where_ = nul()
	if self.eat_kw("WHERE"):
		has_where = true
		where_ = self.parse_or()?
	var group_by = List[Ex]()
	if self.eat_kw("GROUP"):
		self.expect_kw("BY")?
		group_by.append(self.parse_colref()?)
		while self.eat_op(","):
			group_by.append(self.parse_colref()?)
	var has_having = false
	var having = nul()
	if self.eat_kw("HAVING"):
		has_having = true
		having = self.parse_or()?
	var order = List[OrderItem]()
	if self.eat_kw("ORDER"):
		self.expect_kw("BY")?
		while true:
			e := self.parse_or()?
			var desc = false
			if self.eat_kw("DESC"):
				desc = true
			else:
				self.eat_kw("ASC")
			order.append(OrderItem(e, desc))
			if not self.eat_op(","): break
	var limit = -1
	var offset = -1
	if self.eat_kw("LIMIT"):
		if self.kind_at(0) != 2: return error(syn())
		limit = self.num_at(0)
		self.pos += 1
		if self.eat_kw("OFFSET"):
			if self.kind_at(0) != 2: return error(syn())
			offset = self.num_at(0)
			self.pos += 1
	return ok(Stmt.Select(Query(distinct, items, refs, jleft, jon, has_where, where_, group_by, has_having, having, order, limit, offset)))

fn var P.parse_stmt() Stmt!:
	if self.eat_kw("SELECT"):
		s := self.parse_select()?
		if not self.at_end(): return error(syn())
		return ok(s)
	if self.eat_kw("CREATE"):
		self.expect_kw("TABLE")?
		name := self.name()?
		self.expect_op("(")?
		var cols = List[ColDef]()
		while true:
			cn := self.name()?
			if self.kind_at(0) != 0: return error(syn())
			ty := self.text_at(0).upper()
			self.pos += 1
			if ty != "INT" and ty != "TEXT": return error(syn())
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
			cols.append(ColDef(cn, ty == "INT", nn, pk))
			if not self.eat_op(","): break
		self.expect_op(")")?
		if not self.at_end(): return error(syn())
		return ok(Stmt.Create(name, cols))
	if self.eat_kw("DROP"):
		self.expect_kw("TABLE")?
		name := self.name()?
		if not self.at_end(): return error(syn())
		return ok(Stmt.Drop(name))
	if self.eat_kw("INSERT"):
		self.expect_kw("INTO")?
		name := self.name()?
		var cols = List[String]()
		var has_cols = false
		if self.eat_op("("):
			has_cols = true
			cols.append(self.name()?)
			while self.eat_op(","):
				cols.append(self.name()?)
			self.expect_op(")")?
		self.expect_kw("VALUES")?
		var rows = List[List[Ex]]()
		while true:
			self.expect_op("(")?
			var row = List[Ex]()
			row.append(self.parse_or()?)
			while self.eat_op(","):
				row.append(self.parse_or()?)
			self.expect_op(")")?
			rows.append(row)
			if not self.eat_op(","): break
		if not self.at_end(): return error(syn())
		return ok(Stmt.Insert(name, cols, has_cols, rows))
	if self.eat_kw("UPDATE"):
		name := self.name()?
		self.expect_kw("SET")?
		var sets = List[SetItem]()
		while true:
			cn := self.name()?
			self.expect_op("=")?
			e := self.parse_or()?
			sets.append(SetItem(cn, e))
			if not self.eat_op(","): break
		var has_where = false
		var where_ = nul()
		if self.eat_kw("WHERE"):
			has_where = true
			where_ = self.parse_or()?
		if not self.at_end(): return error(syn())
		return ok(Stmt.Update(name, sets, has_where, where_))
	if self.eat_kw("DELETE"):
		self.expect_kw("FROM")?
		name := self.name()?
		var has_where = false
		var where_ = nul()
		if self.eat_kw("WHERE"):
			has_where = true
			where_ = self.parse_or()?
		if not self.at_end(): return error(syn())
		return ok(Stmt.Delete(name, has_where, where_))
	return error(syn())

// ---------- values ----------

fn is_null(v: Val) Bool:
	match v:
		Null: return true
		_: return false

fn as_int(v: Val) Int?:
	match v:
		I(n): return n
		_: return none

fn as_text(v: Val) String?:
	match v:
		T(s): return s.clone()
		_: return none

fn show(v: Val) String:
	match v:
		Null: return "NULL"
		I(n): return "{n}"
		T(s): return s.clone()
		B(b): return if b: "true" else: "false"

fn vkey(v: Val) String:
	match v:
		Null: return "n"
		I(n): return "i{n}"
		T(s):
			l := s.length()
			return "t{l}:{s}"
		B(b): return if b: "bt" else: "bf"

fn rank(v: Val) Int:
	match v:
		Null: return 0
		I(_n): return 1
		T(_s): return 2
		B(_b): return 3

fn type_error() Error:
	return Error("type error")

// compares two non-null same-typed values
fn cmp_same(a: Val, b: Val) Int!:
	xa := as_int(a)
	xb := as_int(b)
	if xa.is_some() and xb.is_some():
		x := xa.get(0)
		y := xb.get(0)
		if x < y: return ok(-1)
		if x > y: return ok(1)
		return ok(0)
	ta := as_text(a)
	tb := as_text(b)
	if ta.is_some() and tb.is_some():
		x := ta.get("")
		y := tb.get("")
		if x < y: return ok(-1)
		if x > y: return ok(1)
		return ok(0)
	return error(type_error())

fn sort_cmp(a: Val, b: Val) Int:
	ra := rank(a)
	rb := rank(b)
	if ra != rb:
		return if ra < rb: -1 else: 1
	r := cmp_same(a, b)
	if x := r:
		return x
	return 0

fn compare_op(op: String, a: Val, b: Val) Val!:
	if is_null(a) or is_null(b): return ok(Val.Null)
	c := cmp_same(a, b)?
	res := if op == "=": c == 0 else if op == "<>": c != 0 else if op == "<": c < 0 else if op == "<=": c <= 0 else if op == ">": c > 0 else: c >= 0
	return ok(Val.B(res))

fn arith(op: String, a: Val, b: Val) Val!:
	if is_null(a) or is_null(b): return ok(Val.Null)
	if op == "||":
		ta := as_text(a)
		tb := as_text(b)
		if ta.is_none() or tb.is_none(): return error(type_error())
		return ok(Val.T(ta.get("") + tb.get("")))
	xa := as_int(a)
	xb := as_int(b)
	if xa.is_none() or xb.is_none(): return error(type_error())
	x := xa.get(0)
	y := xb.get(0)
	if op == "+": return ok(Val.I(x + y))
	if op == "-": return ok(Val.I(x - y))
	if op == "*": return ok(Val.I(x * y))
	if y == 0: return error(Error("division by zero"))
	if op == "/": return ok(Val.I(x / y))
	return ok(Val.I(x % y))

fn like_match(s: Bytes, p: Bytes) Bool:
	n := s.length()
	m := p.length()
	var i = 0
	var j = 0
	var star = -1
	var mark = 0
	while i < n:
		if j < m and p.get(j).to_int() == 37:
			star = j
			mark = i
			j += 1
		else if j < m and (p.get(j).to_int() == 95 or p.get(j).to_int() == s.get(i).to_int()):
			i += 1
			j += 1
		else if star >= 0:
			j = star + 1
			mark += 1
			i = mark
		else:
			return false
	while j < m and p.get(j).to_int() == 37:
		j += 1
	return j == m

fn is_bool(v: Val, want: Bool) Bool:
	match v:
		B(b): return b == want
		_: return false

fn tri(v: Val) Val!:
	match v:
		Null: return ok(Val.Null)
		B(b): return ok(Val.B(b))
		_: return error(type_error())

fn negate(v: Val) Val:
	match v:
		B(b): return Val.B(not b)
		_: return Val.Null

fn cond(v: Val) Bool!:
	match v:
		Null: return ok(false)
		B(b): return ok(b)
		_: return error(type_error())

fn is_agg_name(n: String) Bool:
	return n == "COUNT" or n == "SUM" or n == "MIN" or n == "MAX"

fn aggregate(name: String, arg: Ex, star: Bool, distinct: Bool, grp: List[List[Val]]) Val!:
	if star: return ok(Val.I(grp.length()))
	var vals = List[Val]()
	var seen = Set[String]()
	for r in grp:
		v := eval(arg, r, grp, false)?
		if is_null(v): continue
		if distinct:
			k := vkey(v)
			if seen.contains(k): continue
			seen.add(k)
		vals.append(v)
	if name == "COUNT": return ok(Val.I(vals.length()))
	if vals.length() == 0: return ok(Val.Null)
	if name == "SUM":
		var t = 0
		for v in vals:
			x := as_int(v)
			if x.is_none(): return error(type_error())
			t += x.get(0)
		return ok(Val.I(t))
	var best = vals[0].clone()
	for k in 1..vals.length():
		v := vals[k].clone()
		if rank(v) != rank(best): return error(type_error())
		c := cmp_same(v, best)?
		if name == "MIN" and c < 0:
			best = v
		else if name == "MAX" and c > 0:
			best = v
	return ok(best)

fn eval(e: Ex, row: List[Val], grp: List[List[Val]], grouped: Bool) Val!:
	match e:
		Lit(v): return ok(v.clone())
		Col(_q, _n): return error(Error("internal: unresolved column"))
		Ref(i, _n):
			if grouped:
				if grp.length() == 0: return ok(Val.Null)
				return ok(grp[0][i].clone())
			return ok(row[i].clone())
		Neg(x):
			v := eval(x, row, grp, grouped)?
			match v:
				Null: return ok(Val.Null)
				I(n): return ok(Val.I(0 - n))
				_: return error(type_error())
		Arith(op, l, r):
			a := eval(l, row, grp, grouped)?
			b := eval(r, row, grp, grouped)?
			return arith(op, a, b)
		Cmp(op, l, r):
			a := eval(l, row, grp, grouped)?
			b := eval(r, row, grp, grouped)?
			return compare_op(op, a, b)
		And(l, r):
			a := tri(eval(l, row, grp, grouped)?)?
			if is_bool(a, false): return ok(Val.B(false))
			b := tri(eval(r, row, grp, grouped)?)?
			if is_bool(b, false): return ok(Val.B(false))
			if is_null(a) or is_null(b): return ok(Val.Null)
			return ok(Val.B(true))
		Or(l, r):
			a := tri(eval(l, row, grp, grouped)?)?
			if is_bool(a, true): return ok(Val.B(true))
			b := tri(eval(r, row, grp, grouped)?)?
			if is_bool(b, true): return ok(Val.B(true))
			if is_null(a) or is_null(b): return ok(Val.Null)
			return ok(Val.B(false))
		Not(x):
			v := tri(eval(x, row, grp, grouped)?)?
			return ok(negate(v))
		IsNull(x, neg):
			v := eval(x, row, grp, grouped)?
			return ok(Val.B(is_null(v) != neg))
		Like(x, p, neg):
			a := eval(x, row, grp, grouped)?
			b := eval(p, row, grp, grouped)?
			if is_null(a) or is_null(b): return ok(Val.Null)
			ta := as_text(a)
			tb := as_text(b)
			if ta.is_none() or tb.is_none(): return error(type_error())
			m := like_match(ta.get("").as_bytes(), tb.get("").as_bytes())
			return ok(Val.B(m != neg))
		In(x, xs, neg):
			a := eval(x, row, grp, grouped)?
			var found = false
			var sawnull = false
			for y in xs:
				b := eval(y, row, grp, grouped)?
				if is_null(a): continue
				if is_null(b):
					sawnull = true
					continue
				c := cmp_same(a, b)?
				if c == 0: found = true
			if is_null(a): return ok(Val.Null)
			if found: return ok(Val.B(not neg))
			if sawnull: return ok(Val.Null)
			return ok(Val.B(neg))
		Between(x, lo, hi, neg):
			a := eval(x, row, grp, grouped)?
			l := eval(lo, row, grp, grouped)?
			c1 := compare_op(">=", a, l)?
			h := eval(hi, row, grp, grouped)?
			c2 := compare_op("<=", a, h)?
			var res = Val.Null
			match c1:
				B(p):
					match c2:
						B(q): res = Val.B(p and q)
						_: res = if p: Val.Null else: Val.B(false)
				_:
					match c2:
						B(q): res = if q: Val.Null else: Val.B(false)
						_: res = Val.Null
			if neg: res = negate(res)
			return ok(res)
		Call(name, args, distinct, star):
			if is_agg_name(name):
				if star: return aggregate(name, nul(), true, distinct, grp)
				return aggregate(name, args[0], false, distinct, grp)
			var vs = List[Val]()
			for a in args:
				vs.append(eval(a, row, grp, grouped)?)
			if name == "COALESCE":
				for v in vs:
					if not is_null(v): return ok(v.clone())
				return ok(Val.Null)
			for v in vs:
				if is_null(v): return ok(Val.Null)
			if name == "UPPER" or name == "LOWER":
				t := as_text(vs[0])
				if t.is_none(): return error(type_error())
				return ok(Val.T(if name == "UPPER": t.get("").upper() else: t.get("").lower()))
			if name == "LENGTH":
				t := as_text(vs[0])
				if t.is_none(): return error(type_error())
				return ok(Val.I(t.get("").length()))
			if name == "ABS":
				x := as_int(vs[0])
				if x.is_none(): return error(type_error())
				n := x.get(0)
				return ok(Val.I(if n < 0: 0 - n else: n))
			// SUBSTR
			t := as_text(vs[0])
			s := as_int(vs[1])
			l := as_int(vs[2])
			if t.is_none() or s.is_none() or l.is_none(): return error(type_error())
			str := t.get("")
			n := str.length()
			st := s.get(0)
			ln := l.get(0)
			if ln <= 0: return ok(Val.T(""))
			lo := if st < 1: 1 else: st
			var hi = n
			if st <= n and ln < n - st + 1:
				hi = st + ln - 1
			if lo > hi: return ok(Val.T(""))
			sub := str.slice(lo - 1, hi)?
			return ok(Val.T(sub))

// ---------- resolution ----------

fn find_col(sc: List[ColInfo], q: String, name: String) Int!:
	var found = -1
	var count = 0
	for i in 0..sc.length():
		if sc[i].name == name and (q == "" or sc[i].alias == q):
			if count == 0: found = i
			count += 1
	if count > 1: return error(Error("ambiguous column: {name}"))
	if count == 0:
		if q == "": return error(Error("no such column: {name}"))
		return error(Error("no such column: {q}.{name}"))
	return ok(found)

fn resolve_list(xs: List[Ex], sc: List[ColInfo], agg_ok: Bool, in_agg: Bool) List[Ex]!:
	var out = List[Ex]()
	for x in xs:
		out.append(resolve(x, sc, agg_ok, in_agg)?)
	return ok(out)

fn resolve(e: Ex, sc: List[ColInfo], agg_ok: Bool, in_agg: Bool) Ex!:
	match e:
		Lit(v): return ok(Ex.Lit(v.clone()))
		Col(q, name):
			i := find_col(sc, q, name)?
			return ok(Ex.Ref(i, name.clone()))
		Ref(i, name): return ok(Ex.Ref(i, name.clone()))
		Neg(x): return ok(Ex.Neg(resolve(x, sc, agg_ok, in_agg)?))
		Arith(op, l, r):
			a := resolve(l, sc, agg_ok, in_agg)?
			b := resolve(r, sc, agg_ok, in_agg)?
			return ok(Ex.Arith(op.clone(), a, b))
		Cmp(op, l, r):
			a := resolve(l, sc, agg_ok, in_agg)?
			b := resolve(r, sc, agg_ok, in_agg)?
			return ok(Ex.Cmp(op.clone(), a, b))
		And(l, r):
			a := resolve(l, sc, agg_ok, in_agg)?
			b := resolve(r, sc, agg_ok, in_agg)?
			return ok(Ex.And(a, b))
		Or(l, r):
			a := resolve(l, sc, agg_ok, in_agg)?
			b := resolve(r, sc, agg_ok, in_agg)?
			return ok(Ex.Or(a, b))
		Not(x): return ok(Ex.Not(resolve(x, sc, agg_ok, in_agg)?))
		IsNull(x, neg): return ok(Ex.IsNull(resolve(x, sc, agg_ok, in_agg)?, neg))
		Like(x, p, neg):
			a := resolve(x, sc, agg_ok, in_agg)?
			b := resolve(p, sc, agg_ok, in_agg)?
			return ok(Ex.Like(a, b, neg))
		In(x, xs, neg):
			a := resolve(x, sc, agg_ok, in_agg)?
			b := resolve_list(xs, sc, agg_ok, in_agg)?
			return ok(Ex.In(a, b, neg))
		Between(x, lo, hi, neg):
			a := resolve(x, sc, agg_ok, in_agg)?
			b := resolve(lo, sc, agg_ok, in_agg)?
			c := resolve(hi, sc, agg_ok, in_agg)?
			return ok(Ex.Between(a, b, c, neg))
		Call(name, args, distinct, star):
			n := args.length()
			if is_agg_name(name):
				if not agg_ok or in_agg: return error(Error("misuse of aggregate"))
				if not star and n != 1: return error(Error("wrong number of arguments to {name}"))
				if star and n != 0: return error(Error("wrong number of arguments to {name}"))
				a := resolve_list(args, sc, true, true)?
				return ok(Ex.Call(name.clone(), a, distinct, star))
			var want = -1
			if name == "UPPER" or name == "LOWER" or name == "LENGTH" or name == "ABS":
				want = 1
			else if name == "SUBSTR":
				want = 3
			else if name == "COALESCE":
				want = 0
			else:
				return error(Error("no such function: {name}"))
			if name == "COALESCE":
				if n < 1: return error(Error("wrong number of arguments to {name}"))
			else if n != want:
				return error(Error("wrong number of arguments to {name}"))
			if distinct and n != 1: return error(Error("wrong number of arguments to {name}"))
			a := resolve_list(args, sc, agg_ok, in_agg)?
			return ok(Ex.Call(name.clone(), a, distinct, star))

fn has_agg(e: Ex) Bool:
	match e:
		Lit(_v): return false
		Col(_q, _n): return false
		Ref(_i, _n): return false
		Neg(x): return has_agg(x)
		Arith(_op, l, r): return has_agg(l) or has_agg(r)
		Cmp(_op, l, r): return has_agg(l) or has_agg(r)
		And(l, r): return has_agg(l) or has_agg(r)
		Or(l, r): return has_agg(l) or has_agg(r)
		Not(x): return has_agg(x)
		IsNull(x, _neg): return has_agg(x)
		Like(x, p, _neg): return has_agg(x) or has_agg(p)
		In(x, xs, _neg):
			if has_agg(x): return true
			for y in xs:
				if has_agg(y): return true
			return false
		Between(x, lo, hi, _neg): return has_agg(x) or has_agg(lo) or has_agg(hi)
		Call(name, args, _d, _s):
			if is_agg_name(name): return true
			for y in args:
				if has_agg(y): return true
			return false

fn gcheck(e: Ex, gset: Set[Int]) Unit!:
	match e:
		Lit(_v): return ok(unit)
		Col(_q, _n): return ok(unit)
		Ref(i, name):
			if not gset.contains(i): return error(Error("column {name} must appear in GROUP BY"))
			return ok(unit)
		Neg(x): return gcheck(x, gset)
		Arith(_op, l, r):
			gcheck(l, gset)?
			return gcheck(r, gset)
		Cmp(_op, l, r):
			gcheck(l, gset)?
			return gcheck(r, gset)
		And(l, r):
			gcheck(l, gset)?
			return gcheck(r, gset)
		Or(l, r):
			gcheck(l, gset)?
			return gcheck(r, gset)
		Not(x): return gcheck(x, gset)
		IsNull(x, _neg): return gcheck(x, gset)
		Like(x, p, _neg):
			gcheck(x, gset)?
			return gcheck(p, gset)
		In(x, xs, _neg):
			gcheck(x, gset)?
			for y in xs:
				gcheck(y, gset)?
			return ok(unit)
		Between(x, lo, hi, _neg):
			gcheck(x, gset)?
			gcheck(lo, gset)?
			return gcheck(hi, gset)
		Call(name, args, _d, _s):
			if is_agg_name(name): return ok(unit)
			for y in args:
				gcheck(y, gset)?
			return ok(unit)

// ---------- execution ----------

fn find_table(db: Db, name: String) Int:
	for i in 0..db.tables.length():
		if db.tables[i].name == name: return i
	return -1

fn clone_row(r: List[Val]) List[Val]:
	var out = List[Val]()
	for v in r:
		out.append(v.clone())
	return out

fn table_scope(t: Table, alias: String) List[ColInfo]:
	var sc = List[ColInfo]()
	for c in t.cols:
		sc.append(ColInfo(alias.clone(), c.name.clone()))
	return sc

fn cmp_keys(a: List[Val], b: List[Val], descs: List[Bool]) Int:
	for i in 0..a.length():
		c := sort_cmp(a[i], b[i])
		if c != 0:
			return if descs[i]: 0 - c else: c
	return 0

fn run_select(db: Db, q: Query) String!:
	var tidx = List[Int]()
	for r in q.refs:
		ti := find_table(db, r.name)
		if ti < 0: return error(Error("no such table: {r.name}"))
		tidx.append(ti)
	var sc = List[ColInfo]()
	var seen = Set[String]()
	for r in q.refs:
		if seen.contains(r.alias): return error(Error("duplicate alias: {r.alias}"))
		seen.add(r.alias.clone())
	// rows and join conditions (resolved progressively)
	var rows = List[List[Val]]()
	if q.refs.length() == 0:
		rows.append(List[Val]())
	for k in 0..q.refs.length():
		t := db.tables[tidx[k]]
		for c in t.cols:
			sc.append(ColInfo(q.refs[k].alias.clone(), c.name.clone()))
		if k == 0:
			for r in t.rows:
				rows.append(clone_row(r))
		else:
			on := resolve(q.jon[k - 1], sc, false, false)?
			left := q.jleft[k - 1]
			var nrows = List[List[Val]]()
			for outer in rows:
				var matched = false
				for inner in t.rows:
					var comb = clone_row(outer)
					for v in inner:
						comb.append(v.clone())
					ok1 := cond(eval(on, comb, [], false)?)?
					if ok1:
						matched = true
						nrows.append(comb)
				if left and not matched:
					var comb = clone_row(outer)
					for _c in t.cols:
						comb.append(Val.Null)
					nrows.append(comb)
			rows = nrows
	// stars
	for it in q.items:
		if it.kind == 2:
			var f = false
			for c in sc:
				if c.alias == it.tname: f = true
			if not f: return error(Error("no such table: {it.tname}"))
	var gidx = List[Int]()
	var gset = Set[Int]()
	for g in q.group_by:
		match g:
			Col(gq, gn):
				i := find_col(sc, gq, gn)?
				gidx.append(i)
				gset.add(i)
			_: gidx.append(0)
	var where_ = nul()
	if q.has_where:
		where_ = resolve(q.where_, sc, false, false)?
	var items = List[Ex]()
	var names = List[String]()
	for it in q.items:
		if it.kind == 1:
			for i in 0..sc.length():
				items.append(Ex.Ref(i, sc[i].name.clone()))
				names.append(sc[i].name.clone())
		else if it.kind == 2:
			for i in 0..sc.length():
				if sc[i].alias == it.tname:
					items.append(Ex.Ref(i, sc[i].name.clone()))
					names.append(sc[i].name.clone())
		else:
			items.append(resolve(it.e, sc, true, false)?)
			if it.has_alias:
				names.append(it.alias.clone())
			else:
				match it.e:
					Col(_q, cn): names.append(cn.clone())
					_: names.append("?column?")
	var having = nul()
	if q.has_having:
		having = resolve(q.having, sc, true, false)?
	var specs = List[OrdSpec]()
	var aggregated = q.group_by.length() > 0 or q.has_having
	for it in q.items:
		if it.kind == 0 and has_agg(it.e): aggregated = true
	for o in q.order:
		var pos = -1
		var handled = false
		match o.e:
			Lit(v):
				x := as_int(v)
				if x.is_some():
					n := x.get(0)
					if n < 1 or n > names.length(): return error(Error("bad ORDER BY position"))
					pos = n - 1
					handled = true
			Col(cq, cn):
				if cq == "":
					for i in 0..names.length():
						if names[i] == cn:
							pos = i
							handled = true
							break
			_: handled = false
		if handled:
			specs.append(OrdSpec(pos, nul(), o.desc))
		else:
			if has_agg(o.e): aggregated = true
			specs.append(OrdSpec(-1, resolve(o.e, sc, true, false)?, o.desc))
	if aggregated:
		for x in items:
			gcheck(x, gset)?
		if q.has_having: gcheck(having, gset)?
		for s in specs:
			if s.pos < 0: gcheck(s.e, gset)?
	// evaluation
	var filtered = List[List[Val]]()
	for r in rows:
		if q.has_where:
			if not cond(eval(where_, r, [], false)?)?: continue
		filtered.append(r.clone())
	var outs = List[List[Val]]()
	var srcs = List[Int]()
	var groups = List[List[List[Val]]]()
	if aggregated:
		if gidx.length() == 0:
			groups.append(filtered.clone())
		else:
			var gm = Map[String, Int]()
			for r in filtered:
				var key = ""
				for i in gidx:
					key = key + vkey(r[i]) + "|"
				if gi := gm.get(key):
					groups[gi].append(clone_row(r))
				else:
					gm[key] = groups.length()
					var ng = List[List[Val]]()
					ng.append(clone_row(r))
					groups.append(ng)
		var kept = List[Int]()
		for gi in 0..groups.length():
			if q.has_having:
				if not cond(eval(having, [], groups[gi], true)?)?: continue
			kept.append(gi)
		for gi in kept:
			var o = List[Val]()
			for x in items:
				o.append(eval(x, [], groups[gi], true)?)
			outs.append(o)
			srcs.append(gi)
	else:
		for ri in 0..filtered.length():
			var o = List[Val]()
			for x in items:
				o.append(eval(x, filtered[ri], [], false)?)
			outs.append(o)
			srcs.append(ri)
	var rr = List[RRow]()
	var dseen = Set[String]()
	for k in 0..outs.length():
		if q.distinct:
			var key = ""
			for v in outs[k]:
				key = key + vkey(v) + "|"
			if dseen.contains(key): continue
			dseen.add(key)
		var keys = List[Val]()
		for s in specs:
			if s.pos >= 0:
				keys.append(outs[k][s.pos].clone())
			else if aggregated:
				keys.append(eval(s.e, [], groups[srcs[k]], true)?)
			else:
				keys.append(eval(s.e, filtered[srcs[k]], [], false)?)
		rr.append(RRow(clone_row(outs[k]), keys, srcs[k]))
	var descs = List[Bool]()
	for s in specs:
		descs.append(s.desc)
	if specs.length() > 0:
		rr.sort(fn(a: RRow, b: RRow) Int: cmp_keys(a.keys, b.keys, descs))
	var start = 0
	if q.offset > 0: start = q.offset
	var end = rr.length()
	if q.limit >= 0 and start + q.limit < end: end = start + q.limit
	var lines = List[String]()
	lines.append(names.join("|"))
	var count = 0
	var idx = start
	while idx < end:
		var parts = List[String]()
		for v in rr[idx].out:
			parts.append(show(v))
		lines.append(parts.join("|"))
		count += 1
		idx += 1
	lines.append("({count} rows)")
	return ok(lines.join("\n"))

fn check_row(t: Table, row: List[Val]) Unit!:
	for i in 0..t.cols.length():
		c := t.cols[i]
		v := row[i]
		if is_null(v):
			if c.notnull or c.pk: return error(Error("NOT NULL constraint failed: {c.name}"))
		else:
			if c.is_int:
				if as_int(v).is_none(): return error(Error("type mismatch in column {c.name}"))
			else:
				if as_text(v).is_none(): return error(Error("type mismatch in column {c.name}"))
	return ok(unit)

fn pk_index(t: Table) Int:
	for i in 0..t.cols.length():
		if t.cols[i].pk: return i
	return -1

fn check_pk(t: Table, rows: List[List[Val]]) Unit!:
	p := pk_index(t)
	if p < 0: return ok(unit)
	var seen = Set[String]()
	for r in rows:
		k := vkey(r[p])
		if seen.contains(k): return error(Error("duplicate primary key: {show(r[p])}"))
		seen.add(k)
	return ok(unit)

fn exec(var db: Db, st: Stmt) String!:
	match st:
		Create(name, cols):
			if find_table(db, name) >= 0: return error(Error("table {name} already exists"))
			var pks = 0
			for i in 0..cols.length():
				for j in 0..i:
					if cols[i].name == cols[j].name: return error(Error("duplicate column: {cols[i].name}"))
			for c in cols:
				if c.pk: pks += 1
			if pks > 1: return error(Error("multiple primary keys"))
			var cs = List[ColDef]()
			for c in cols:
				cs.append(ColDef(c.name.clone(), c.is_int, c.notnull or c.pk, c.pk))
			db.tables.append(Table(name.clone(), cs, List[List[Val]]()))
			return ok("ok")
		Drop(name):
			i := find_table(db, name)
			if i < 0: return error(Error("no such table: {name}"))
			var nt = List[Table]()
			for k in 0..db.tables.length():
				if k != i: nt.append(db.tables[k].clone())
			db.tables = nt
			return ok("ok")
		Insert(table, cols, has_cols, rows):
			ti := find_table(db, table)
			if ti < 0: return error(Error("no such table: {table}"))
			t := db.tables[ti]
			var map = List[Int]()
			if has_cols:
				for cn in cols:
					var f = -1
					for i in 0..t.cols.length():
						if t.cols[i].name == cn: f = i
					if f < 0: return error(Error("no such column: {cn}"))
					for m in map:
						if m == f: return error(Error("duplicate column: {cn}"))
					map.append(f)
			else:
				for i in 0..t.cols.length():
					map.append(i)
			var newrows = List[List[Val]]()
			var empty = List[ColInfo]()
			for r in rows:
				if r.length() != map.length(): return error(Error("wrong number of values"))
				var row = List[Val]()
				for _c in t.cols:
					row.append(Val.Null)
				for k in 0..r.length():
					ex := resolve(r[k], empty, false, false)?
					v := eval(ex, [], [], false)?
					row[map[k]] = v
				check_row(t, row)?
				newrows.append(row)
			var all = List[List[Val]]()
			for r in t.rows:
				all.append(clone_row(r))
			for r in newrows:
				all.append(clone_row(r))
			check_pk(t, all)?
			db.tables[ti].rows = all
			return ok("inserted {newrows.length()}")
		Update(table, sets, has_where, where_):
			ti := find_table(db, table)
			if ti < 0: return error(Error("no such table: {table}"))
			t := db.tables[ti]
			var cidx = List[Int]()
			for s in sets:
				var f = -1
				for i in 0..t.cols.length():
					if t.cols[i].name == s.name: f = i
				if f < 0: return error(Error("no such column: {s.name}"))
				cidx.append(f)
			sc := table_scope(t, table)
			var exs = List[Ex]()
			for s in sets:
				exs.append(resolve(s.e, sc, false, false)?)
			var w = nul()
			if has_where: w = resolve(where_, sc, false, false)?
			var nrows = List[List[Val]]()
			var cnt = 0
			for r in t.rows:
				var match_ = true
				if has_where:
					match_ = cond(eval(w, r, [], false)?)?
				if match_:
					cnt += 1
					var nr = clone_row(r)
					for k in 0..exs.length():
						nr[cidx[k]] = eval(exs[k], r, [], false)?
					check_row(t, nr)?
					nrows.append(nr)
				else:
					nrows.append(clone_row(r))
			check_pk(t, nrows)?
			db.tables[ti].rows = nrows
			return ok("updated {cnt}")
		Delete(table, has_where, where_):
			ti := find_table(db, table)
			if ti < 0: return error(Error("no such table: {table}"))
			t := db.tables[ti]
			sc := table_scope(t, table)
			var w = nul()
			if has_where: w = resolve(where_, sc, false, false)?
			var nrows = List[List[Val]]()
			var cnt = 0
			for r in t.rows:
				var del = true
				if has_where:
					del = cond(eval(w, r, [], false)?)?
				if del:
					cnt += 1
				else:
					nrows.append(clone_row(r))
			db.tables[ti].rows = nrows
			return ok("deleted {cnt}")
		Select(q): return run_select(db, q)

fn run_one(var db: Db, src: String) String!:
	toks := lex(src)?
	if toks.length() == 0: return ok("")
	var p = P(toks)
	st := p.parse_stmt()?
	return exec(var db, st)

// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin())?
	src := data.decode_utf8().get("")
	var db = Db(List[Table]())
	for s in split_script(src):
		r := run_one(var db, s)
		if out := r:
			if out != "": print(out)
		else:
			print("error: {r.err().message}")
