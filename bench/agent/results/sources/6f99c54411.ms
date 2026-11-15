import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import BytesBuilder, Bytes from "@std/bytes.ms"

enum Value:
	VNull
	VInt(n: Int)
	VText(s: String)
	VBool(b: Bool)

enum Expr:
	Lit(v: Value)
	Col(q: String, name: String)
	Neg(e: Expr)
	Bin(op: String, l: Expr, r: Expr)
	And(l: Expr, r: Expr)
	Or(l: Expr, r: Expr)
	Not(e: Expr)
	IsNull(e: Expr, neg: Bool)
	Like(e: Expr, p: Expr, neg: Bool)
	In(e: Expr, list: List[Expr], neg: Bool)
	Between(e: Expr, lo: Expr, hi: Expr, neg: Bool)
	Call(name: String, args: List[Expr], distinct: Bool, star: Bool)

type Col:
	alias: String
	name: String

type ColDef:
	name: String
	is_int: Bool
	notnull: Bool
	pk: Bool

type Table:
	name: String
	cols: List[ColDef]
	rows: List[List[Value]]

type Db:
	tables: List[Table]

type TRef:
	name: String
	alias: String

type Join:
	left: Bool
	t: TRef
	on: Expr

type Item:
	star: Bool
	qual: String
	e: Expr?
	alias: String

type OrderItem:
	e: Expr
	desc: Bool

type Sel:
	distinct: Bool
	items: List[Item]
	has_from: Bool
	base: TRef
	joins: List[Join]
	cond: Expr?
	group: List[Expr]
	having: Expr?
	order: List[OrderItem]
	limit: Int
	offset: Int

enum Stmt:
	Create(name: String, cols: List[ColDef])
	Drop(name: String)
	Insert(name: String, cols: List[String], rows: List[List[Expr]])
	Update(name: String, setcols: List[String], setexprs: List[Expr], cond: Expr?)
	Delete(name: String, cond: Expr?)
	Select(sel: Sel)

type Tok:
	kind: Int
	text: String
	n: Int

type OutRow:
	vals: List[Value]
	keys: List[Value]

type Plan:
	pos: Int
	e: Expr
	desc: Bool

// ---------- value helpers ----------

fn byte(b: Bytes, i: Int) Int: b.get(i, 0).to_int()

fn ub(x: Int) UInt8: x.to_uint8().get(0)

fn is_null(v: Value) Bool:
	match v:
		VNull: return true
		_: return false

fn as_int(v: Value) Int?:
	match v:
		VInt(n): return n
		_: return none

fn as_text(v: Value) String?:
	match v:
		VText(s): return s.clone()
		_: return none

fn show(v: Value) String:
	match v:
		VNull: return "NULL"
		VInt(n): return "{n}"
		VText(s): return s.clone()
		VBool(b): return "{b}"

fn vkey(v: Value) String:
	match v:
		VNull: return "N"
		VInt(n): return "I{n};"
		VText(s): return "T{s.length()}:{s}"
		VBool(b): return "B{b}"

fn rank(v: Value) Int:
	match v:
		VNull: return 0
		VBool(_b): return 1
		VInt(_n): return 2
		VText(_s): return 3

fn cmpv(a: Value, b: Value) Int:
	ra := rank(a)
	rb := rank(b)
	if ra != rb:
		if ra < rb: return -1
		return 1
	if x := as_int(a):
		if y := as_int(b):
			if x < y: return -1
			if x > y: return 1
			return 0
	if x := as_text(a):
		if y := as_text(b):
			if x < y: return -1
			if x > y: return 1
			return 0
	return 0

fn type_err() Error: Error("type error")

fn cmp_same(a: Value, b: Value) Int!:
	if x := as_int(a):
		if y := as_int(b):
			if x < y: return ok(-1)
			if x > y: return ok(1)
			return ok(0)
	if x := as_text(a):
		if y := as_text(b):
			if x < y: return ok(-1)
			if x > y: return ok(1)
			return ok(0)
	return error(type_err())

fn compare(op: String, a: Value, b: Value) Value!:
	if is_null(a) or is_null(b): return ok(Value.VNull)
	c := cmp_same(a, b)?
	r := if op == "=": c == 0 else if op == "<>": c != 0 else if op == "<": c < 0 else if op == "<=": c <= 0 else if op == ">": c > 0 else: c >= 0
	return ok(Value.VBool(r))

fn arith(op: String, a: Value, b: Value) Value!:
	if is_null(a) or is_null(b): return ok(Value.VNull)
	if op == "||":
		if x := as_text(a):
			if y := as_text(b):
				return ok(Value.VText(x + y))
		return error(type_err())
	if x := as_int(a):
		if y := as_int(b):
			if op == "+": return ok(Value.VInt(x + y))
			if op == "-": return ok(Value.VInt(x - y))
			if op == "*": return ok(Value.VInt(x * y))
			if y == 0: return error(Error("division by zero"))
			if op == "/": return ok(Value.VInt(x / y))
			return ok(Value.VInt(x % y))
	return error(type_err())

fn like_match(s: Bytes, p: Bytes) Bool:
	sl := s.length()
	pl := p.length()
	var si = 0
	var pi = 0
	var star = -1
	var mark = 0
	while si < sl:
		if pi < pl and byte(p, pi) == 37:
			star = pi
			mark = si
			pi += 1
		else if pi < pl and (byte(p, pi) == 95 or byte(p, pi) == byte(s, si)):
			si += 1
			pi += 1
		else if star >= 0:
			pi = star + 1
			mark += 1
			si = mark
		else:
			return false
	while pi < pl and byte(p, pi) == 37:
		pi += 1
	return pi == pl

fn case_map(s: String, up: Bool) String:
	b := s.as_bytes()
	var bb = BytesBuilder()
	for i in 0..b.length():
		c := byte(b, i)
		if up and c >= 97 and c <= 122:
			bb.append(ub(c - 32))
		else if not up and c >= 65 and c <= 90:
			bb.append(ub(c + 32))
		else:
			bb.append(ub(c))
	return bb.build().decode_utf8().get("")

fn is_agg(up: String) Bool:
	return up == "COUNT" or up == "SUM" or up == "MIN" or up == "MAX"

// ---------- name resolution ----------

fn resolve(cols: List[Col], q: String, name: String) Int!:
	var found = -1
	var count = 0
	for i in 0..cols.length():
		if cols[i].name == name and (q == "" or cols[i].alias == q):
			if found < 0: found = i
			count += 1
	if count == 0:
		if q == "": return error(Error("no such column: {name}"))
		return error(Error("no such column: {q}.{name}"))
	if count > 1: return error(Error("ambiguous column: {name}"))
	return ok(found)

fn check_list(es: List[Expr], cols: List[Col], allow_agg: Bool, in_agg: Bool, grouped: Bool, gcols: List[Int]) Unit!:
	for x in es:
		check(x, cols, allow_agg, in_agg, grouped, gcols)?

fn check(e: Expr, cols: List[Col], allow_agg: Bool, in_agg: Bool, grouped: Bool, gcols: List[Int]) Unit!:
	match e:
		Lit(_v): return ok(unit)
		Col(q, name):
			i := resolve(cols, q, name)?
			if grouped and not in_agg and not gcols.contains(i):
				return error(Error("column {name} must appear in GROUP BY"))
			return ok(unit)
		Neg(x): check(x, cols, allow_agg, in_agg, grouped, gcols)?
		Bin(_op, l, r):
			check(l, cols, allow_agg, in_agg, grouped, gcols)?
			check(r, cols, allow_agg, in_agg, grouped, gcols)?
		And(l, r):
			check(l, cols, allow_agg, in_agg, grouped, gcols)?
			check(r, cols, allow_agg, in_agg, grouped, gcols)?
		Or(l, r):
			check(l, cols, allow_agg, in_agg, grouped, gcols)?
			check(r, cols, allow_agg, in_agg, grouped, gcols)?
		Not(x): check(x, cols, allow_agg, in_agg, grouped, gcols)?
		IsNull(x, _neg): check(x, cols, allow_agg, in_agg, grouped, gcols)?
		Like(x, p, _neg):
			check(x, cols, allow_agg, in_agg, grouped, gcols)?
			check(p, cols, allow_agg, in_agg, grouped, gcols)?
		In(x, list, _neg):
			check(x, cols, allow_agg, in_agg, grouped, gcols)?
			check_list(list, cols, allow_agg, in_agg, grouped, gcols)?
		Between(x, lo, hi, _neg):
			check(x, cols, allow_agg, in_agg, grouped, gcols)?
			check(lo, cols, allow_agg, in_agg, grouped, gcols)?
			check(hi, cols, allow_agg, in_agg, grouped, gcols)?
		Call(name, args, _distinct, star):
			up := name.upper()
			if is_agg(up):
				if not star and args.length() != 1:
					return error(Error("wrong number of arguments to {up}"))
				if not allow_agg or in_agg:
					return error(Error("misuse of aggregate"))
				check_list(args, cols, allow_agg, true, grouped, gcols)?
			else:
				n := args.length()
				if up == "UPPER" or up == "LOWER" or up == "LENGTH" or up == "ABS":
					if n != 1: return error(Error("wrong number of arguments to {up}"))
				else if up == "SUBSTR":
					if n != 3: return error(Error("wrong number of arguments to {up}"))
				else if up == "COALESCE":
					if n < 1: return error(Error("wrong number of arguments to {up}"))
				else:
					return error(Error("no such function: {up}"))
				check_list(args, cols, allow_agg, in_agg, grouped, gcols)?
	return ok(unit)

fn contains_agg(e: Expr) Bool:
	match e:
		Lit(_v): return false
		Col(_q, _n): return false
		Neg(x): return contains_agg(x)
		Bin(_op, l, r): return contains_agg(l) or contains_agg(r)
		And(l, r): return contains_agg(l) or contains_agg(r)
		Or(l, r): return contains_agg(l) or contains_agg(r)
		Not(x): return contains_agg(x)
		IsNull(x, _neg): return contains_agg(x)
		Like(x, p, _neg): return contains_agg(x) or contains_agg(p)
		In(x, list, _neg):
			if contains_agg(x): return true
			for y in list:
				if contains_agg(y): return true
			return false
		Between(x, lo, hi, _neg): return contains_agg(x) or contains_agg(lo) or contains_agg(hi)
		Call(name, args, _d, _s):
			if is_agg(name.upper()): return true
			for y in args:
				if contains_agg(y): return true
			return false

// ---------- evaluation ----------

fn bool_of(v: Value) Bool?!:
	match v:
		VBool(b): return ok(b)
		VNull: return ok(none)
		_: return error(type_err())

fn eval_list(es: List[Expr], cols: List[Col], row: List[Value], rows: List[List[Value]], idx: List[Int], grouped: Bool) List[Value]!:
	var out = List[Value]()
	for x in es:
		out.append(eval(x, cols, row, rows, idx, grouped)?)
	return ok(out)

fn aggregate(name: String, distinct: Bool, star: Bool, args: List[Expr], cols: List[Col], rows: List[List[Value]], idx: List[Int]) Value!:
	if star: return ok(Value.VInt(idx.length()))
	var vals = List[Value]()
	var seen = Set[String]()
	empty := List[List[Value]]()
	noidx := List[Int]()
	for k in idx:
		v := eval(args[0], cols, rows[k], empty, noidx, false)?
		if is_null(v): continue
		if distinct:
			key := vkey(v)
			if seen.contains(key): continue
			seen.add(key)
		vals.append(v)
	if name == "COUNT": return ok(Value.VInt(vals.length()))
	if vals.length() == 0: return ok(Value.VNull)
	if name == "SUM":
		var total = 0
		for v in vals:
			if x := as_int(v):
				total += x
			else:
				return error(type_err())
		return ok(Value.VInt(total))
	var best = vals[0].clone()
	for i in 1..vals.length():
		c := cmp_same(best, vals[i])?
		if name == "MIN" and c > 0: best = vals[i].clone()
		if name == "MAX" and c < 0: best = vals[i].clone()
	if vals.length() == 1:
		c := cmp_same(best, best)?
		if c != 0: return error(type_err())
	return ok(best)

fn scalar(up: String, vals: List[Value]) Value!:
	if up == "COALESCE":
		for v in vals:
			if not is_null(v): return ok(v.clone())
		return ok(Value.VNull)
	for v in vals:
		if is_null(v): return ok(Value.VNull)
	if up == "UPPER" or up == "LOWER":
		if s := as_text(vals[0]):
			return ok(Value.VText(case_map(s, up == "UPPER")))
		return error(type_err())
	if up == "LENGTH":
		if s := as_text(vals[0]):
			return ok(Value.VInt(s.length()))
		return error(type_err())
	if up == "ABS":
		if x := as_int(vals[0]):
			if x < 0: return ok(Value.VInt(0 - x))
			return ok(Value.VInt(x))
		return error(type_err())
	if s := as_text(vals[0]):
		if st := as_int(vals[1]):
			if ln := as_int(vals[2]):
				b := s.as_bytes()
				l := b.length()
				lo := if st < 1: 1 else: st
				var hi = st + ln - 1
				if hi > l: hi = l
				if ln <= 0 or lo > hi: return ok(Value.VText(""))
				return ok(Value.VText(b.decode_utf8_range(lo - 1, hi).get("")))
	return error(type_err())

fn eval(e: Expr, cols: List[Col], row: List[Value], rows: List[List[Value]], idx: List[Int], grouped: Bool) Value!:
	match e:
		Lit(v): return ok(v.clone())
		Col(q, name):
			i := resolve(cols, q, name)?
			return ok(row[i].clone())
		Neg(x):
			v := eval(x, cols, row, rows, idx, grouped)?
			if is_null(v): return ok(Value.VNull)
			if n := as_int(v): return ok(Value.VInt(0 - n))
			return error(type_err())
		Bin(op, l, r):
			a := eval(l, cols, row, rows, idx, grouped)?
			b := eval(r, cols, row, rows, idx, grouped)?
			if op == "+" or op == "-" or op == "*" or op == "/" or op == "%" or op == "||":
				return arith(op, a, b)
			return compare(op, a, b)
		And(l, r):
			a := bool_of(eval(l, cols, row, rows, idx, grouped)?)?
			if x := a:
				if not x: return ok(Value.VBool(false))
			b := bool_of(eval(r, cols, row, rows, idx, grouped)?)?
			if y := b:
				if not y: return ok(Value.VBool(false))
				if a.is_none(): return ok(Value.VNull)
				return ok(Value.VBool(true))
			return ok(Value.VNull)
		Or(l, r):
			a := bool_of(eval(l, cols, row, rows, idx, grouped)?)?
			if x := a:
				if x: return ok(Value.VBool(true))
			b := bool_of(eval(r, cols, row, rows, idx, grouped)?)?
			if y := b:
				if y: return ok(Value.VBool(true))
				if a.is_none(): return ok(Value.VNull)
				return ok(Value.VBool(false))
			return ok(Value.VNull)
		Not(x):
			a := bool_of(eval(x, cols, row, rows, idx, grouped)?)?
			if y := a: return ok(Value.VBool(not y))
			return ok(Value.VNull)
		IsNull(x, neg):
			v := eval(x, cols, row, rows, idx, grouped)?
			return ok(Value.VBool(is_null(v) != neg))
		Like(x, p, neg):
			a := eval(x, cols, row, rows, idx, grouped)?
			b := eval(p, cols, row, rows, idx, grouped)?
			if is_null(a) or is_null(b): return ok(Value.VNull)
			if s := as_text(a):
				if pt := as_text(b):
					m := like_match(s.as_bytes(), pt.as_bytes())
					return ok(Value.VBool(m != neg))
			return error(type_err())
		In(x, list, neg):
			a := eval(x, cols, row, rows, idx, grouped)?
			var found = false
			var sawnull = false
			for y in list:
				b := eval(y, cols, row, rows, idx, grouped)?
				c := compare("=", a, b)?
				match c:
					VBool(t):
						if t: found = true
					_: sawnull = true
			if found: return ok(Value.VBool(not neg))
			if sawnull: return ok(Value.VNull)
			return ok(Value.VBool(neg))
		Between(x, lo, hi, neg):
			a := eval(x, cols, row, rows, idx, grouped)?
			l := eval(lo, cols, row, rows, idx, grouped)?
			h := eval(hi, cols, row, rows, idx, grouped)?
			ge := bool_of(compare(">=", a, l)?)?
			var res: Bool? = none
			var decided = false
			if g := ge:
				if not g:
					res = false
					decided = true
			if not decided:
				le := bool_of(compare("<=", a, h)?)?
				if lv := le:
					if not lv:
						res = false
					else if ge.is_some():
						res = true
			if r := res:
				return ok(Value.VBool(r != neg))
			return ok(Value.VNull)
		Call(name, args, distinct, star):
			up := name.upper()
			if is_agg(up):
				return aggregate(up, distinct, star, args, cols, rows, idx)
			vals := eval_list(args, cols, row, rows, idx, grouped)?
			return scalar(up, vals)

fn cond_true(e: Expr, cols: List[Col], row: List[Value], rows: List[List[Value]], idx: List[Int], grouped: Bool) Bool!:
	v := eval(e, cols, row, rows, idx, grouped)?
	match v:
		VBool(b): return ok(b)
		VNull: return ok(false)
		_: return error(type_err())

// ---------- lexer ----------

fn synerr() Error: Error("syntax error")

fn is_keyword(s: String) Bool:
	kws := ["SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT", "OFFSET", "JOIN", "LEFT", "INNER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "LIKE", "IN", "BETWEEN", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "DISTINCT", "ASC", "DESC"]
	return kws.contains(s)

fn is_alpha(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_digit(c: Int) Bool: c >= 48 and c <= 57

// kinds: 0 ident, 1 keyword, 2 int, 3 string, 4 op, 5 eof
fn lex(src: String) List[Tok]!:
	b := src.as_bytes()
	n := b.length()
	var toks = List[Tok]()
	var i = 0
	while i < n:
		c := byte(b, i)
		if c == 32 or c == 9 or c == 13 or c == 10:
			i += 1
		else if c == 45 and byte(b, i + 1) == 45:
			while i < n and byte(b, i) != 10:
				i += 1
		else if is_digit(c):
			start := i
			while i < n and is_digit(byte(b, i)):
				i += 1
			text := b.decode_utf8_range(start, i).get("")
			v := text.parse_int()
			if x := v:
				toks.append(Tok(kind: 2, text: text, n: x))
			else:
				return error(synerr())
		else if is_alpha(c):
			start := i
			while i < n and (is_alpha(byte(b, i)) or is_digit(byte(b, i))):
				i += 1
			text := b.decode_utf8_range(start, i).get("")
			up := text.upper()
			if is_keyword(up):
				toks.append(Tok(kind: 1, text: up, n: 0))
			else:
				toks.append(Tok(kind: 0, text: text, n: 0))
		else if c == 39:
			var bb = BytesBuilder()
			var j = i + 1
			while true:
				if j >= n: return error(synerr())
				ch := byte(b, j)
				if ch == 39:
					if byte(b, j + 1) == 39 and j + 1 < n:
						bb.append(ub(39))
						j += 2
					else:
						break
				else:
					bb.append(ub(ch))
					j += 1
			i = j + 1
			toks.append(Tok(kind: 3, text: bb.build().decode_utf8().get(""), n: 0))
		else:
			c2 := byte(b, i + 1)
			if (c == 60 and (c2 == 62 or c2 == 61)) or (c == 62 and c2 == 61) or (c == 33 and c2 == 61) or (c == 124 and c2 == 124):
				text := b.decode_utf8_range(i, i + 2).get("")
				toks.append(Tok(kind: 4, text: if text == "!=": "<>" else: text, n: 0))
				i += 2
			else if c == 61 or c == 60 or c == 62 or c == 43 or c == 45 or c == 42 or c == 47 or c == 37 or c == 40 or c == 41 or c == 44 or c == 46:
				toks.append(Tok(kind: 4, text: b.decode_utf8_range(i, i + 1).get(""), n: 0))
				i += 1
			else:
				return error(synerr())
	toks.append(Tok(kind: 5, text: "", n: 0))
	return ok(toks)

fn split_statements(src: String) List[String]:
	b := src.as_bytes()
	n := b.length()
	var out = List[String]()
	var start = 0
	var i = 0
	var in_str = false
	while i < n:
		c := byte(b, i)
		if in_str:
			if c == 39: in_str = false
			i += 1
		else if c == 39:
			in_str = true
			i += 1
		else if c == 45 and byte(b, i + 1) == 45:
			while i < n and byte(b, i) != 10:
				i += 1
		else if c == 59:
			out.append(b.decode_utf8_range(start, i).get(""))
			i += 1
			start = i
		else:
			i += 1
	out.append(b.decode_utf8_range(start, n).get(""))
	return out

// ---------- parser ----------

type Parser:
	toks: List[Tok]
	pos: Int

fn Parser.at(off: Int) Int:
	i := self.pos + off
	if i >= self.toks.length(): return self.toks.length() - 1
	return i

fn Parser.kind() Int: self.toks[self.pos].kind

fn Parser.kind_at(off: Int) Int: self.toks[self.at(off)].kind

fn Parser.kw(k: String) Bool: self.toks[self.pos].kind == 1 and self.toks[self.pos].text == k

fn Parser.kw_at(off: Int, k: String) Bool:
	t := self.toks[self.at(off)]
	return t.kind == 1 and t.text == k

fn Parser.op(o: String) Bool: self.toks[self.pos].kind == 4 and self.toks[self.pos].text == o

fn Parser.op_at(off: Int, o: String) Bool:
	t := self.toks[self.at(off)]
	return t.kind == 4 and t.text == o

fn var Parser.next() Unit:
	if self.pos < self.toks.length() - 1: self.pos += 1

fn var Parser.eat_kw(k: String) Bool:
	if self.kw(k):
		self.next()
		return true
	return false

fn var Parser.eat_op(o: String) Bool:
	if self.op(o):
		self.next()
		return true
	return false

fn var Parser.expect_kw(k: String) Unit!:
	if not self.eat_kw(k): return error(synerr())

fn var Parser.expect_op(o: String) Unit!:
	if not self.eat_op(o): return error(synerr())

fn var Parser.ident() String!:
	if self.kind() != 0: return error(synerr())
	t := self.toks[self.pos].text.clone()
	self.next()
	return ok(t)

fn var Parser.parse_expr() Expr!:
	return self.parse_or()

fn var Parser.parse_or() Expr!:
	var l = self.parse_and()?
	while self.eat_kw("OR"):
		r := self.parse_and()?
		l = Expr.Or(l, r)
	return ok(l)

fn var Parser.parse_and() Expr!:
	var l = self.parse_not()?
	while self.eat_kw("AND"):
		r := self.parse_not()?
		l = Expr.And(l, r)
	return ok(l)

fn var Parser.parse_not() Expr!:
	if self.eat_kw("NOT"):
		x := self.parse_not()?
		return ok(Expr.Not(x))
	return self.parse_cmp()

fn var Parser.parse_cmp() Expr!:
	l := self.parse_add()?
	if self.kind() == 4:
		t := self.toks[self.pos].text.clone()
		if t == "=" or t == "<>" or t == "<" or t == "<=" or t == ">" or t == ">=":
			self.next()
			r := self.parse_add()?
			return ok(Expr.Bin(t, l, r))
		return ok(l)
	if self.eat_kw("IS"):
		neg := self.eat_kw("NOT")
		self.expect_kw("NULL")?
		return ok(Expr.IsNull(l, neg))
	var neg = false
	if self.kw("NOT") and (self.kw_at(1, "LIKE") or self.kw_at(1, "IN") or self.kw_at(1, "BETWEEN")):
		self.next()
		neg = true
	if self.eat_kw("LIKE"):
		p := self.parse_add()?
		return ok(Expr.Like(l, p, neg))
	if self.eat_kw("IN"):
		self.expect_op("(")?
		var list = List[Expr]()
		while true:
			list.append(self.parse_expr()?)
			if not self.eat_op(","): break
		self.expect_op(")")?
		return ok(Expr.In(l, list, neg))
	if self.eat_kw("BETWEEN"):
		lo := self.parse_add()?
		self.expect_kw("AND")?
		hi := self.parse_add()?
		return ok(Expr.Between(l, lo, hi, neg))
	return ok(l)

fn var Parser.parse_add() Expr!:
	var l = self.parse_mul()?
	while self.op("+") or self.op("-") or self.op("||"):
		t := self.toks[self.pos].text.clone()
		self.next()
		r := self.parse_mul()?
		l = Expr.Bin(t, l, r)
	return ok(l)

fn var Parser.parse_mul() Expr!:
	var l = self.parse_unary()?
	while self.op("*") or self.op("/") or self.op("%"):
		t := self.toks[self.pos].text.clone()
		self.next()
		r := self.parse_unary()?
		l = Expr.Bin(t, l, r)
	return ok(l)

fn var Parser.parse_unary() Expr!:
	if self.eat_op("-"):
		x := self.parse_unary()?
		return ok(Expr.Neg(x))
	return self.parse_primary()

fn var Parser.parse_primary() Expr!:
	k := self.kind()
	if k == 2:
		n := self.toks[self.pos].n
		self.next()
		return ok(Expr.Lit(Value.VInt(n)))
	if k == 3:
		s := self.toks[self.pos].text.clone()
		self.next()
		return ok(Expr.Lit(Value.VText(s)))
	if self.eat_kw("NULL"): return ok(Expr.Lit(Value.VNull))
	if self.eat_op("("):
		x := self.parse_expr()?
		self.expect_op(")")?
		return ok(x)
	if k == 0:
		name := self.ident()?
		if self.eat_op("("):
			var args = List[Expr]()
			var distinct = false
			var star = false
			if self.eat_op(")"):
				return ok(Expr.Call(name, args, false, false))
			if self.eat_kw("DISTINCT"):
				distinct = true
				args.append(self.parse_expr()?)
			else if self.op("*"):
				if name.upper() != "COUNT": return error(synerr())
				self.next()
				star = true
			else:
				while true:
					args.append(self.parse_expr()?)
					if not self.eat_op(","): break
			self.expect_op(")")?
			return ok(Expr.Call(name, args, distinct, star))
		if self.eat_op("."):
			c := self.ident()?
			return ok(Expr.Col(name, c))
		return ok(Expr.Col("", name))
	return error(synerr())

fn var Parser.parse_colref() Expr!:
	name := self.ident()?
	if self.eat_op("."):
		c := self.ident()?
		return ok(Expr.Col(name, c))
	return ok(Expr.Col("", name))

fn var Parser.parse_tref() TRef!:
	name := self.ident()?
	var alias = ""
	if self.eat_kw("AS"):
		alias = self.ident()?
	else if self.kind() == 0:
		alias = self.ident()?
	return ok(TRef(name: name, alias: alias))

fn var Parser.parse_item() Item!:
	if self.eat_op("*"):
		return ok(Item(star: true, qual: "", e: none, alias: ""))
	if self.kind() == 0 and self.op_at(1, ".") and self.op_at(2, "*"):
		q := self.ident()?
		self.next()
		self.next()
		return ok(Item(star: true, qual: q, e: none, alias: ""))
	x := self.parse_expr()?
	var alias = ""
	if self.eat_kw("AS"):
		alias = self.ident()?
	return ok(Item(star: false, qual: "", e: x, alias: alias))

fn var Parser.parse_select() Sel!:
	self.next()
	distinct := self.eat_kw("DISTINCT")
	var items = List[Item]()
	while true:
		items.append(self.parse_item()?)
		if not self.eat_op(","): break
	var has_from = false
	var base = TRef(name: "", alias: "")
	var joins = List[Join]()
	if self.eat_kw("FROM"):
		has_from = true
		base = self.parse_tref()?
		while true:
			var left = false
			if self.kw("LEFT"):
				self.next()
				left = true
				self.expect_kw("JOIN")?
			else if self.kw("INNER"):
				self.next()
				self.expect_kw("JOIN")?
			else if self.kw("JOIN"):
				self.next()
			else:
				break
			t := self.parse_tref()?
			self.expect_kw("ON")?
			on := self.parse_expr()?
			joins.append(Join(left: left, t: t, on: on))
	var cond: Expr? = none
	if self.eat_kw("WHERE"):
		cond = self.parse_expr()?
	var group = List[Expr]()
	if self.eat_kw("GROUP"):
		self.expect_kw("BY")?
		while true:
			group.append(self.parse_colref()?)
			if not self.eat_op(","): break
	var having: Expr? = none
	if self.eat_kw("HAVING"):
		having = self.parse_expr()?
	var order = List[OrderItem]()
	if self.eat_kw("ORDER"):
		self.expect_kw("BY")?
		while true:
			x := self.parse_expr()?
			var desc = false
			if self.eat_kw("DESC"):
				desc = true
			else:
				self.eat_kw("ASC")
			order.append(OrderItem(e: x, desc: desc))
			if not self.eat_op(","): break
	var limit = -1
	var offset = 0
	if self.eat_kw("LIMIT"):
		if self.kind() != 2: return error(synerr())
		limit = self.toks[self.pos].n
		self.next()
		if self.eat_kw("OFFSET"):
			if self.kind() != 2: return error(synerr())
			offset = self.toks[self.pos].n
			self.next()
	return ok(Sel(distinct: distinct, items: items, has_from: has_from, base: base, joins: joins, cond: cond, group: group, having: having, order: order, limit: limit, offset: offset))

fn var Parser.parse_stmt() Stmt!:
	if self.kw("SELECT"):
		s := self.parse_select()?
		return ok(Stmt.Select(s))
	if self.eat_kw("CREATE"):
		self.expect_kw("TABLE")?
		name := self.ident()?
		self.expect_op("(")?
		var cols = List[ColDef]()
		while true:
			cn := self.ident()?
			tn := self.ident()?
			up := tn.upper()
			if up != "INT" and up != "TEXT": return error(synerr())
			var notnull = false
			var pk = false
			while true:
				if self.eat_kw("PRIMARY"):
					self.expect_kw("KEY")?
					pk = true
				else if self.eat_kw("NOT"):
					self.expect_kw("NULL")?
					notnull = true
				else:
					break
			cols.append(ColDef(name: cn, is_int: up == "INT", notnull: notnull or pk, pk: pk))
			if not self.eat_op(","): break
		self.expect_op(")")?
		return ok(Stmt.Create(name, cols))
	if self.eat_kw("DROP"):
		self.expect_kw("TABLE")?
		name := self.ident()?
		return ok(Stmt.Drop(name))
	if self.eat_kw("INSERT"):
		self.expect_kw("INTO")?
		name := self.ident()?
		var cols = List[String]()
		if self.eat_op("("):
			while true:
				cols.append(self.ident()?)
				if not self.eat_op(","): break
			self.expect_op(")")?
		self.expect_kw("VALUES")?
		var rows = List[List[Expr]]()
		while true:
			self.expect_op("(")?
			var row = List[Expr]()
			while true:
				row.append(self.parse_expr()?)
				if not self.eat_op(","): break
			self.expect_op(")")?
			rows.append(row)
			if not self.eat_op(","): break
		return ok(Stmt.Insert(name, cols, rows))
	if self.eat_kw("UPDATE"):
		name := self.ident()?
		self.expect_kw("SET")?
		var cs = List[String]()
		var es = List[Expr]()
		while true:
			cs.append(self.ident()?)
			self.expect_op("=")?
			es.append(self.parse_expr()?)
			if not self.eat_op(","): break
		var cond: Expr? = none
		if self.eat_kw("WHERE"):
			cond = self.parse_expr()?
		return ok(Stmt.Update(name, cs, es, cond))
	if self.eat_kw("DELETE"):
		self.expect_kw("FROM")?
		name := self.ident()?
		var cond: Expr? = none
		if self.eat_kw("WHERE"):
			cond = self.parse_expr()?
		return ok(Stmt.Delete(name, cond))
	return error(synerr())

// ---------- execution ----------

fn find_table(db: Db, name: String) Int:
	for i in 0..db.tables.length():
		if db.tables[i].name == name: return i
	return -1

fn check_row(t: Table, row: List[Value]) Unit!:
	for i in 0..t.cols.length():
		c := t.cols[i]
		v := row[i]
		if is_null(v):
			if c.notnull: return error(Error("NOT NULL constraint failed: {c.name}"))
		else:
			good := match v:
				VInt(_n): c.is_int
				VText(_s): not c.is_int
				_: false
			if not good: return error(Error("type mismatch in column {c.name}"))

fn check_pk(t: Table, rows: List[List[Value]]) Unit!:
	var pk = -1
	for i in 0..t.cols.length():
		if t.cols[i].pk: pk = i
	if pk < 0: return ok(unit)
	var seen = Set[String]()
	for r in rows:
		k := vkey(r[pk])
		if seen.contains(k):
			return error(Error("duplicate primary key: {show(r[pk])}"))
		seen.add(k)

fn prefix(cols: List[Col], n: Int) List[Col]:
	var out = List[Col]()
	for i in 0..n:
		out.append(Col(alias: cols[i].alias.clone(), name: cols[i].name.clone()))
	return out

fn cmp_out(a: OutRow, b: OutRow, descs: List[Bool]) Int:
	for k in 0..descs.length():
		c := cmpv(a.keys[k], b.keys[k])
		if c != 0:
			if descs[k]: return 0 - c
			return c
	return 0

fn row_key(vals: List[Value]) String:
	var s = ""
	for v in vals:
		s = s + vkey(v)
	return s

fn run_select(db: Db, s: Sel) String!:
	var cols = List[Col]()
	var ends = List[Int]()
	var tabs = List[Int]()
	var aliases = List[String]()
	var trefs = List[TRef]()
	if s.has_from:
		trefs.append(TRef(name: s.base.name.clone(), alias: s.base.alias.clone()))
		for j in s.joins:
			trefs.append(TRef(name: j.t.name.clone(), alias: j.t.alias.clone()))
	for r in trefs:
		ti := find_table(db, r.name)
		if ti < 0: return error(Error("no such table: {r.name}"))
		alias := if r.alias == "": r.name.clone() else: r.alias.clone()
		if aliases.contains(alias): return error(Error("duplicate alias: {alias}"))
		aliases.append(alias.clone())
		tabs.append(ti)
		for c in db.tables[ti].cols:
			cols.append(Col(alias: alias.clone(), name: c.name.clone()))
		ends.append(cols.length())
	noidx := List[Int]()
	// join conditions
	for j in 0..s.joins.length():
		pc := prefix(cols, ends[j + 1])
		check(s.joins[j].on, pc, false, false, false, noidx)?
	// stars
	for it in s.items:
		if it.star and it.qual != "":
			if not aliases.contains(it.qual): return error(Error("no such table: {it.qual}"))
	// group by
	var gcols = List[Int]()
	for g in s.group:
		match g:
			Col(q, name):
				gcols.append(resolve(cols, q, name)?)
			_: return error(synerr())
	// where
	if w := s.cond:
		check(w, cols, false, false, false, noidx)?
	// aggregated?
	var aggregated = s.group.length() > 0 or s.having.is_some()
	for it in s.items:
		if x := it.e:
			if contains_agg(x): aggregated = true
	for o in s.order:
		if contains_agg(o.e): aggregated = true
	// expand items
	var names = List[String]()
	var exprs = List[Expr]()
	for it in s.items:
		if it.star:
			for i in 0..cols.length():
				if it.qual == "" or cols[i].alias == it.qual:
					names.append(cols[i].name.clone())
					exprs.append(Expr.Col(cols[i].alias.clone(), cols[i].name.clone()))
		else if x := it.e:
			check(x, cols, true, false, aggregated, gcols)?
			var nm = "?column?"
			if it.alias != "":
				nm = it.alias.clone()
			else:
				match x:
					Col(_q, name): nm = name.clone()
					_: nm = "?column?"
			names.append(nm)
			exprs.append(x.clone())
	if h := s.having:
		check(h, cols, true, false, true, gcols)?
	// order by
	var plans = List[Plan]()
	var descs = List[Bool]()
	for o in s.order:
		var pos = -1
		match o.e:
			Lit(v):
				if n := as_int(v):
					if n < 1 or n > names.length(): return error(Error("bad ORDER BY position"))
					pos = n - 1
			Col(q, name):
				if q == "":
					for i in 0..names.length():
						if names[i] == name and pos < 0: pos = i
			_: pos = -1
		match o.e:
			Lit(v):
				if pos < 0 and as_int(v).is_none():
					check(o.e, cols, true, false, aggregated, gcols)?
			_:
				if pos < 0:
					check(o.e, cols, true, false, aggregated, gcols)?
		plans.append(Plan(pos: pos, e: o.e.clone(), desc: o.desc))
		descs.append(o.desc)
	// rows
	var cur = List[List[Value]]()
	if not s.has_from:
		cur.append(List[Value]())
	else:
		for r in db.tables[tabs[0]].rows:
			cur.append(r.clone())
	emptyrows := List[List[Value]]()
	for j in 0..s.joins.length():
		ti := tabs[j + 1]
		pc := prefix(cols, ends[j + 1])
		width := db.tables[ti].cols.length()
		var nxt = List[List[Value]]()
		for o in cur:
			var matched = false
			for inr in db.tables[ti].rows:
				var comb = o.clone()
				for v in inr:
					comb.append(v.clone())
				if cond_true(s.joins[j].on, pc, comb, emptyrows, noidx, false)?:
					matched = true
					nxt.append(comb)
			if s.joins[j].left and not matched:
				var comb = o.clone()
				for _k in 0..width:
					comb.append(Value.VNull)
				nxt.append(comb)
		cur = nxt
	var rows = List[List[Value]]()
	if w := s.cond:
		for r in cur:
			if cond_true(w, cols, r, emptyrows, noidx, false)?:
				rows.append(r.clone())
	else:
		rows = cur
	var outs = List[OutRow]()
	if aggregated:
		var groups = List[List[Int]]()
		if s.group.length() == 0:
			var all = List[Int]()
			for i in 0..rows.length():
				all.append(i)
			groups.append(all)
		else:
			var gm = Map[String, Int]()
			for i in 0..rows.length():
				var key = ""
				for gi in gcols:
					key = key + vkey(rows[i][gi])
				if gi := gm.get(key):
					groups[gi].append(i)
				else:
					gm[key] = groups.length()
					var ng = List[Int]()
					ng.append(i)
					groups.append(ng)
		for g in groups:
			row := if g.length() > 0: rows[g[0]].clone() else: List[Value]()
			if h := s.having:
				if not cond_true(h, cols, row, rows, g, true)?: continue
			var vals = List[Value]()
			for x in exprs:
				vals.append(eval(x, cols, row, rows, g, true)?)
			var keys = List[Value]()
			for p in plans:
				if p.pos >= 0:
					keys.append(vals[p.pos].clone())
				else:
					keys.append(eval(p.e, cols, row, rows, g, true)?)
			outs.append(OutRow(vals: vals, keys: keys))
	else:
		for i in 0..rows.length():
			var vals = List[Value]()
			for x in exprs:
				vals.append(eval(x, cols, rows[i], emptyrows, noidx, false)?)
			var keys = List[Value]()
			for p in plans:
				if p.pos >= 0:
					keys.append(vals[p.pos].clone())
				else:
					keys.append(eval(p.e, cols, rows[i], emptyrows, noidx, false)?)
			outs.append(OutRow(vals: vals, keys: keys))
	if s.distinct:
		var seen = Set[String]()
		var uniq = List[OutRow]()
		for o in outs:
			k := row_key(o.vals)
			if seen.contains(k): continue
			seen.add(k)
			uniq.append(OutRow(vals: o.vals.clone(), keys: o.keys.clone()))
		outs = uniq
	if plans.length() > 0:
		outs.sort(fn a, b: cmp_out(a, b, descs))
	var lines = List[String]()
	lines.append(names.join("|"))
	var emitted = 0
	for i in 0..outs.length():
		if i < s.offset: continue
		if s.limit >= 0 and emitted >= s.limit: break
		var parts = List[String]()
		for v in outs[i].vals:
			parts.append(show(v))
		lines.append(parts.join("|"))
		emitted += 1
	lines.append("({emitted} rows)")
	return ok(lines.join("\n"))

fn run_stmt(var db: Db, text: String) String!:
	toks := lex(text)?
	if toks.length() == 1: return ok("")
	var p = Parser(toks: toks, pos: 0)
	stmt := p.parse_stmt()?
	if p.kind() != 5: return error(synerr())
	emptyrows := List[List[Value]]()
	noidx := List[Int]()
	match stmt:
		Select(s): return run_select(db, s)
		Create(name, cdefs):
			if find_table(db, name) >= 0: return error(Error("table {name} already exists"))
			var pks = 0
			for i in 0..cdefs.length():
				for j in 0..i:
					if cdefs[j].name == cdefs[i].name: return error(Error("duplicate column: {cdefs[i].name}"))
				if cdefs[i].pk: pks += 1
			if pks > 1: return error(Error("multiple primary keys"))
			var cl = List[ColDef]()
			for c in cdefs:
				cl.append(ColDef(name: c.name.clone(), is_int: c.is_int, notnull: c.notnull, pk: c.pk))
			db.tables.append(Table(name: name.clone(), cols: cl, rows: List[List[Value]]()))
			return ok("ok")
		Drop(name):
			ti := find_table(db, name)
			if ti < 0: return error(Error("no such table: {name}"))
			db.tables.remove(ti)
			return ok("ok")
		Insert(name, icols, irows):
			ti := find_table(db, name)
			if ti < 0: return error(Error("no such table: {name}"))
			t := db.tables[ti]
			var map = List[Int]()
			if icols.length() == 0:
				for i in 0..t.cols.length():
					map.append(i)
			else:
				for cn in icols:
					var f = -1
					for i in 0..t.cols.length():
						if t.cols[i].name == cn: f = i
					if f < 0: return error(Error("no such column: {cn}"))
					if map.contains(f): return error(Error("duplicate column: {cn}"))
					map.append(f)
			var newrows = List[List[Value]]()
			nocols := List[Col]()
			for r in irows:
				if r.length() != map.length(): return error(Error("wrong number of values"))
				for x in r:
					check(x, nocols, false, false, false, noidx)?
				var vals = List[Value]()
				for x in r:
					vals.append(eval(x, nocols, List[Value](), emptyrows, noidx, false)?)
				var row = List[Value]()
				for _i in 0..t.cols.length():
					row.append(Value.VNull)
				for k in 0..map.length():
					row[map[k]] = vals[k].clone()
				check_row(t, row)?
				newrows.append(row)
			var all = List[List[Value]]()
			for r in t.rows:
				all.append(r.clone())
			for r in newrows:
				all.append(r.clone())
			check_pk(t, all)?
			n := newrows.length()
			db.tables[ti].rows = all
			return ok("inserted {n}")
		Update(name, setcols, setexprs, cond):
			ti := find_table(db, name)
			if ti < 0: return error(Error("no such table: {name}"))
			t := db.tables[ti]
			var cols = List[Col]()
			for c in t.cols:
				cols.append(Col(alias: name.clone(), name: c.name.clone()))
			var sidx = List[Int]()
			for cn in setcols:
				var f = -1
				for i in 0..t.cols.length():
					if t.cols[i].name == cn: f = i
				if f < 0: return error(Error("no such column: {cn}"))
				sidx.append(f)
			for x in setexprs:
				check(x, cols, false, false, false, noidx)?
			if w := cond:
				check(w, cols, false, false, false, noidx)?
			var newrows = List[List[Value]]()
			var count = 0
			for r in t.rows:
				var matched = true
				if w := cond:
					matched = cond_true(w, cols, r, emptyrows, noidx, false)?
				var nr = r.clone()
				if matched:
					var newvals = List[Value]()
					for x in setexprs:
						newvals.append(eval(x, cols, r, emptyrows, noidx, false)?)
					for k in 0..sidx.length():
						nr[sidx[k]] = newvals[k].clone()
					check_row(t, nr)?
					count += 1
				newrows.append(nr)
			check_pk(t, newrows)?
			db.tables[ti].rows = newrows
			return ok("updated {count}")
		Delete(name, cond):
			ti := find_table(db, name)
			if ti < 0: return error(Error("no such table: {name}"))
			t := db.tables[ti]
			var cols = List[Col]()
			for c in t.cols:
				cols.append(Col(alias: name.clone(), name: c.name.clone()))
			if w := cond:
				check(w, cols, false, false, false, noidx)?
			var newrows = List[List[Value]]()
			var count = 0
			for r in t.rows:
				var matched = true
				if w := cond:
					matched = cond_true(w, cols, r, emptyrows, noidx, false)?
				if matched:
					count += 1
				else:
					newrows.append(r.clone())
			db.tables[ti].rows = newrows
			return ok("deleted {count}")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	src := data.decode_utf8().get("")
	var db = Db(tables: List[Table]())
	for text in split_statements(src):
		r := run_stmt(var db, text)
		if out := r:
			if out != "": print(out)
		else:
			print("error: {r.err().message}")
