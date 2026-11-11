import (
	stdin from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
	rat_of_float from "@std/math/big.ms",
	floor, pow, sqrt, truncate from "@std/math/math.ms",
)

// ---------------------------------------------------------------- constants

COLS := 26
GRID := 25974
NCHARS_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
N_NUM := 1
N_STR := 2
N_BOOL := 3
N_ERR := 4
N_REF := 5
N_RANGE := 6
N_NAME := 7
N_CALL := 8
N_UNARY := 9
N_BIN := 10
T_NUM := 1
T_STR := 2
T_REF := 3
T_RANGE := 4
T_ERR := 5
T_IDENT := 6
T_OP := 7
T_LP := 8
T_RP := 9
T_COMMA := 10
T_END := 11

// ---------------------------------------------------------------- values

enum Value:
	Empty
	Num(n: Float)
	Txt(s: String)
	Flag(b: Bool)
	Errv(code: String)

fn is_err(v: Value) Bool:
	match v:
		Errv(_c):
			return true
		_:
			return false

fn is_empty(v: Value) Bool:
	match v:
		Empty:
			return true
		_:
			return false

fn is_num(v: Value) Bool:
	match v:
		Num(_n):
			return true
		_:
			return false

fn is_txt(v: Value) Bool:
	match v:
		Txt(_s):
			return true
		_:
			return false

fn num_val(v: Value) Float:
	match v:
		Num(n):
			return n
		_:
			return 0.0

fn flag_val(v: Value) Bool:
	match v:
		Flag(b):
			return b
		_:
			return false

fn txt_val(v: Value) String:
	match v:
		Txt(s):
			return s.clone()
		_:
			return ""

fn finite(x: Float) Value:
	if x.is_finite(): return Value.Num(x)
	return Value.Errv("#NUM!")

// Ranks give the cross-type order: number < text < boolean.
fn rank(v: Value) Int:
	match v:
		Empty:
			return 0
		Num(_n):
			return 1
		Txt(_s):
			return 2
		Flag(_b):
			return 3
		Errv(_c):
			return 4

fn display(v: Value) String:
	match v:
		Empty:
			return ""
		Num(n):
			return fmt_num(n)
		Txt(s):
			return s.clone()
		Flag(b):
			if b: return "TRUE"
			return "FALSE"
		Errv(c):
			return c.clone()

// Exactly 10 fractional digits, correctly rounded, trailing zeros removed.
fn fmt_num(n: Float) String:
	if r := rat_of_float(n):
		var t = r.to_fixed(10).get("0")
		if t.contains("."):
			t = t.trim_end_chars("0").trim_end_chars(".")
		if t == "-0": return "0"

		return t

	return "0"

// Strict number grammar: [+-]?(digits[.digits?]|.digits)([eE][+-]?digits)?, finite.
fn parse_number_text(t: String) Float?:
	cs := t.chars()
	n := cs.length()
	var i = 0
	var neg = false

	if ch(cs, i) == 43 or ch(cs, i) == 45:
		neg = ch(cs, i) == 45
		i += 1

	d0 := i
	while isdig(ch(cs, i)):
		i += 1

	ip := slice_chars(cs, d0, i)
	var fp = ""

	if ch(cs, i) == 46:
		i += 1

		f0 := i
		while isdig(ch(cs, i)):
			i += 1
		fp = slice_chars(cs, f0, i)

	if ip == "" and fp == "": return none

	var ex = "0"
	var eneg = false

	if ch(cs, i) == 101 or ch(cs, i) == 69:
		i += 1

		if ch(cs, i) == 43 or ch(cs, i) == 45:
			eneg = ch(cs, i) == 45
			i += 1

		e0 := i
		while isdig(ch(cs, i)):
			i += 1
		if i == e0: return none

		ex = slice_chars(cs, e0, i)

	if i != n: return none

	var a = ip
	if a == "":
		a = "0"

	var b = fp
	if b == "":
		b = "0"

	var e2 = ex.trim_start_chars("0")
	if e2 == "":
		e2 = "0"

	sign := if neg: "-" else: ""
	sgn := if eneg: "-" else: "+"
	return "{sign}{a}.{b}e{sgn}{e2}".parse_float()

// Value of constant text (already trimmed, non-empty, not starting with "=").
fn classify(raw: String) Value:
	if raw.starts_with("'"): return Value.Txt(raw.drop(1))
	if f := parse_number_text(raw): return Value.Num(f)

	up := raw.upper()
	if up == "TRUE": return Value.Flag(true)
	if up == "FALSE": return Value.Flag(false)

	return Value.Txt(raw.clone())

// Number coercion: numbers, booleans, empty, numeric text; errors pass through.
fn as_num(v: Value) Value:
	match v:
		Num(n):
			return Value.Num(n)
		Flag(b):
			if b: return Value.Num(1.0)
			return Value.Num(0.0)
		Empty:
			return Value.Num(0.0)
		Txt(s):
			if f := parse_number_text(s.trim()): return Value.Num(f)
			return Value.Errv("#VALUE!")
		Errv(c):
			return Value.Errv(c.clone())

// Boolean coercion for IF, NOT, AND, OR.
fn as_flag(v: Value) Value:
	match v:
		Flag(b):
			return Value.Flag(b)
		Num(n):
			return Value.Flag(n != 0.0)
		Empty:
			return Value.Flag(false)
		Txt(s):
			up := s.upper()
			if up == "TRUE": return Value.Flag(true)
			if up == "FALSE": return Value.Flag(false)

			return Value.Errv("#VALUE!")
		Errv(c):
			return Value.Errv(c.clone())

fn zero_like(v: Value) Value:
	match v:
		Num(_n):
			return Value.Num(0.0)
		Txt(_s):
			return Value.Txt("")
		Flag(_b):
			return Value.Flag(false)
		_:
			return Value.Empty

// Three-way comparison of two non-empty values of any type.
fn cmp_vals(a: Value, b: Value) Int:
	ra := rank(a)
	rb := rank(b)

	if ra != rb:
		if ra < rb: return -1
		return 1

	match a:
		Num(x):
			return x.compare(num_val(b))
		Txt(s):
			return s.compare(txt_val(b))
		Flag(p):
			q := flag_val(b)
			if p == q: return 0
			if q: return -1

			return 1
		_:
			return 0

fn op_holds(op: String, c: Int) Bool:
	if op == "=": return c == 0
	if op == "<>": return c != 0
	if op == "<": return c < 0
	if op == "<=": return c <= 0
	if op == ">": return c > 0
	if op == ">=": return c >= 0

	return false

fn is_cmp_op(op: String) Bool:
	return op == "=" or op == "<>" or op == "<" or op == "<=" or op == ">" or op == ">="

fn compare_op(op: String, va: Value, vb: Value) Value:
	if is_err(va): return va.clone()
	if is_err(vb): return vb.clone()

	var c = 0

	if is_empty(va) and is_empty(vb):
		c = 0
	else if is_empty(va):
		c = cmp_vals(zero_like(vb), vb)
	else if is_empty(vb):
		c = cmp_vals(va, zero_like(va))
	else:
		c = cmp_vals(va, vb)

	return Value.Flag(op_holds(op, c))

fn arith(op: String, va: Value, vb: Value) Value:
	a := as_num(va)
	if is_err(a): return a

	b := as_num(vb)
	if is_err(b): return b

	x := num_val(a)
	y := num_val(b)
	var r = 0.0

	if op == "+":
		r = x + y
	else if op == "-":
		r = x - y
	else if op == "*":
		r = x * y
	else if op == "/":
		if y == 0.0: return Value.Errv("#DIV/0!")

		r = x / y
	else:
		r = pow(x, y)

	return finite(r)

// ---------------------------------------------------------------- characters

fn ch(cs: List[String], j: Int) Int:
	if j < 0 or j >= cs.length(): return 0
	return cs[j].scalar_at(0, 0)

fn slice_chars(cs: List[String], a: Int, b: Int) String:
	var out = ""
	var i = a

	while i < b and i < cs.length():
		out = out.concat(cs[i])
		i += 1

	return out

fn isdig(c: Int) Bool:
	return c >= 48 and c <= 57

fn isalpha(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn isword(c: Int) Bool:
	return isalpha(c) or isdig(c) or c == 95 or c == 46 or c == 36

fn isident(c: Int) Bool:
	return isalpha(c) or isdig(c) or c == 95 or c == 46

fn is_ws(c: Int) Bool:
	return c == 32 or c == 9

// Column index 0..25 of an ASCII letter.
fn letter_col(c: Int) Int:
	if c >= 97: return c - 97
	return c - 65

fn col_name(c: Int) String:
	return NCHARS_LETTERS.get(c)

// ---------------------------------------------------------------- references

type Ref:
	col: Int
	row: Int
	valid: Bool
	abs_col: Bool
	abs_row: Bool

fn no_ref() Ref:
	return Ref(col: 0, row: 0, valid: false, abs_col: false, abs_row: false)

// Reads cs[a..b) as $?letters$?digits. none when the text has another shape.
// valid: exactly one letter, 1 to 3 digits, no leading zero.
fn ref_of(cs: List[String], a: Int, b: Int) Ref?:
	var i = a
	var abs_c = false

	if i < b and ch(cs, i) == 36:
		abs_c = true
		i += 1

	l0 := i
	while i < b and isalpha(ch(cs, i)):
		i += 1

	nl := i - l0
	if nl == 0: return none

	var abs_r = false

	if i < b and ch(cs, i) == 36:
		abs_r = true
		i += 1

	d0 := i
	var row = 0

	while i < b and isdig(ch(cs, i)):
		row = row * 10 + (ch(cs, i) - 48)
		i += 1

	nd := i - d0
	if nd == 0 or i != b: return none

	valid := nl == 1 and nd <= 3 and ch(cs, d0) != 48
	var col = 0

	if valid:
		col = letter_col(ch(cs, l0))
	else:
		row = 0

	return Ref(col: col, row: row, valid: valid, abs_col: abs_c, abs_row: abs_r)

fn key_of(col: Int, row: Int) Int:
	return (row - 1) * COLS + col

fn key_col(k: Int) Int:
	return k % COLS

fn key_row(k: Int) Int:
	return k / COLS + 1

fn name_of(k: Int) String:
	return "{col_name(key_col(k))}{key_row(k)}"

// Command-line cell argument: one letter, one to three digits, no $.
fn cell_arg(t: String) Int?:
	cs := t.chars()
	if r := ref_of(cs, 0, cs.length()):
		if r.valid and not r.abs_col and not r.abs_row: return key_of(r.col, r.row)
	return none

fn cell_or_neg(t: String) Int:
	if k := cell_arg(t): return k
	return -1

type Rect:
	c1: Int
	r1: Int
	c2: Int
	r2: Int

fn rect_of_refs(a: Ref, b: Ref) Rect:
	return Rect(
		c1: a.col.min(b.col), r1: a.row.min(b.row), c2: a.col.max(b.col),
		r2: a.row.max(b.row)
	)

fn range_arg(t: String) Rect?:
	parts := t.split(":")

	if parts.length() == 1:
		if k := cell_arg(t):
			return Rect(c1: key_col(k), r1: key_row(k), c2: key_col(k), r2: key_row(k))
		return none

	if parts.length() == 2:
		if a := cell_arg(parts[0]):
			if b := cell_arg(parts[1]):
				return Rect(
					c1: key_col(a).min(key_col(b)), r1: key_row(a).min(key_row(b)),
					c2: key_col(a).max(key_col(b)), r2: key_row(a).max(key_row(b))
				)
	return none

// Keys of a rectangle, row-major.
fn range_keys(rc: Rect) List[Int]:
	var out = List[Int]()
	var r = rc.r1

	while r <= rc.r2:
		var c = rc.c1

		while c <= rc.c2:
			out.append(key_of(c, r))
			c += 1

		r += 1

	return out

fn rect_has(rc: Rect, k: Int) Bool:
	c := key_col(k)
	r := key_row(k)
	return c >= rc.c1 and c <= rc.c2 and r >= rc.r1 and r <= rc.r2

fn any_rect_has(rs: List[Rect], k: Int) Bool:
	for rc in rs:
		if rect_has(rc, k): return true
	return false

// ---------------------------------------------------------------- lexer

type Tok:
	kind: Int
	text: String
	num: Float
	good: Bool
	r1: Ref
	r2: Ref
	start: Int
	stop: Int

fn tok(kind: Int, text: String, a: Int, b: Int) Tok:
	return Tok(
		kind: kind, text: text, num: 0.0, good: true, r1: no_ref(), r2: no_ref(),
		start: a, stop: b
	)

fn scan_number(cs: List[String], i: Int) Int:
	var j = i
	while isdig(ch(cs, j)):
		j += 1

	if ch(cs, j) == 46:
		j += 1
		while isdig(ch(cs, j)):
			j += 1

	e := ch(cs, j)

	if e == 101 or e == 69:
		var k = j + 1
		if ch(cs, k) == 43 or ch(cs, k) == 45:
			k += 1

		if isdig(ch(cs, k)):
			while isdig(ch(cs, k)):
				k += 1
			j = k

	return j

// Identifier shape: letter or underscore, then letters, digits, underscores or dots.
fn ident_shape(cs: List[String], a: Int, b: Int) Bool:
	if b <= a: return false

	first := ch(cs, a)
	if not (isalpha(first) or first == 95): return false

	var i = a

	while i < b:
		if not isident(ch(cs, i)): return false

		i += 1

	return true

fn lex(cs: List[String]) Result[List[Tok], String]:
	var toks = List[Tok]()
	n := cs.length()
	var i = 0

	while i < n:
		c := ch(cs, i)

		if is_ws(c):
			i += 1
		else if isdig(c) or (c == 46 and isdig(ch(cs, i + 1))):
			j := scan_number(cs, i)
			text := slice_chars(cs, i, j)
			var val = 0.0
			var good = false

			if f := parse_number_text(text):
				val = f
				good = true

			toks.append(
				Tok(
					kind: T_NUM, text: text, num: val, good: good, r1: no_ref(),
					r2: no_ref(), start: i, stop: j
				)
			)
			i = j
		else if isalpha(c) or c == 95 or c == 36:
			var j = i
			while isword(ch(cs, j)):
				j += 1

			if ch(cs, j) == 40:
				if not ident_shape(cs, i, j): return error("bad formula")

				toks.append(tok(T_IDENT, slice_chars(cs, i, j), i, j))
				i = j
			else:
				ro := ref_of(cs, i, j)

				if r1 := ro:
					var handled = false

					if ch(cs, j) == 58:
						var k = j + 1
						while isword(ch(cs, k)):
							k += 1

						if ch(cs, k) != 40:
							if r2 := ref_of(cs, j + 1, k):
								toks.append(
									Tok(
										kind: T_RANGE, text: "", num: 0.0, good: true,
										r1: r1.clone(), r2: r2, start: i, stop: k
									)
								)
								i = k
								handled = true

					if not handled:
						toks.append(
							Tok(
								kind: T_REF, text: "", num: 0.0, good: true, r1: r1,
								r2: no_ref(), start: i, stop: j
							)
						)
						i = j
				else if ident_shape(cs, i, j):
					toks.append(tok(T_IDENT, slice_chars(cs, i, j), i, j))
					i = j
				else:
					return error("bad formula")
		else if c == 34:
			var j = i + 1
			var buf = ""
			var closed = false

			while j < n:
				d := ch(cs, j)

				if d == 34:
					if ch(cs, j + 1) == 34:
						buf = buf.concat("\"")
						j += 2
					else:
						closed = true
						j += 1
						break
				else:
					buf = buf.concat(cs[j])
					j += 1

			if not closed: return error("bad formula")

			toks.append(tok(T_STR, buf, i, j))
			i = j
		else if c == 35:
			if slice_chars(cs, i, i + 5) == "#REF!":
				toks.append(tok(T_ERR, "#REF!", i, i + 5))
				i += 5
			else:
				return error("bad formula")
		else if c == 40:
			toks.append(tok(T_LP, "(", i, i + 1))
			i += 1
		else if c == 41:
			toks.append(tok(T_RP, ")", i, i + 1))
			i += 1
		else if c == 44:
			toks.append(tok(T_COMMA, ",", i, i + 1))
			i += 1
		else if c == 60:
			if ch(cs, i + 1) == 61:
				toks.append(tok(T_OP, "<=", i, i + 2))
				i += 2
			else if ch(cs, i + 1) == 62:
				toks.append(tok(T_OP, "<>", i, i + 2))
				i += 2
			else:
				toks.append(tok(T_OP, "<", i, i + 1))
				i += 1
		else if c == 62:
			if ch(cs, i + 1) == 61:
				toks.append(tok(T_OP, ">=", i, i + 2))
				i += 2
			else:
				toks.append(tok(T_OP, ">", i, i + 1))
				i += 1
		else if (
			c == 61
			or c == 43
			or c == 45
			or c == 42
			or c == 47
			or c == 94
			or c == 38
		):
			toks.append(tok(T_OP, slice_chars(cs, i, i + 1), i, i + 1))
			i += 1
		else:
			return error("bad formula")

	toks.append(tok(T_END, "", n, n))
	return ok(toks)

// ---------------------------------------------------------------- parser

type Node:
	kind: Int
	text: String
	num: Float
	flag: Bool
	r1: Ref
	r2: Ref
	args: List[Node]

fn leaf(kind: Int, text: String) Node:
	return Node(
		kind: kind, text: text, num: 0.0, flag: false, r1: no_ref(), r2: no_ref(),
		args: List[Node]()
	)

fn bin_node(op: String, a: Node, b: Node) Node:
	var args = List[Node]()
	args.append(a)
	args.append(b)
	return Node(
		kind: N_BIN, text: op, num: 0.0, flag: false, r1: no_ref(), r2: no_ref(),
		args: args
	)

fn un_node(op: String, a: Node) Node:
	var args = List[Node]()
	args.append(a)
	return Node(
		kind: N_UNARY, text: op, num: 0.0, flag: false, r1: no_ref(), r2: no_ref(),
		args: args
	)

type Parser:
	toks: List[Tok]
	pos: Int
	bad: Bool

impl Parser:
	fn kind_now() Int:
		return self.toks[self.pos].kind

	fn text_now() String:
		return self.toks[self.pos].text.clone()

	var fn step() Unit:
		if self.pos < self.toks.length() - 1:
			self.pos += 1

	var fn parse_expr() Node:
		var left = self.parse_concat()

		while not self.bad and self.kind_now() == T_OP and is_cmp_op(self.text_now()):
			op := self.text_now()
			self.step()

			right := self.parse_concat()
			left = bin_node(op, left, right)

		return left

	var fn parse_concat() Node:
		var left = self.parse_additive()

		while not self.bad and self.kind_now() == T_OP and self.text_now() == "&":
			self.step()

			right := self.parse_additive()
			left = bin_node("&", left, right)

		return left

	var fn parse_additive() Node:
		var left = self.parse_mult()

		while (
			not self.bad
			and self.kind_now() == T_OP
			and (self.text_now() == "+" or self.text_now() == "-")
		):
			op := self.text_now()
			self.step()

			right := self.parse_mult()
			left = bin_node(op, left, right)

		return left

	var fn parse_mult() Node:
		var left = self.parse_unary()

		while (
			not self.bad
			and self.kind_now() == T_OP
			and (self.text_now() == "*" or self.text_now() == "/")
		):
			op := self.text_now()
			self.step()

			right := self.parse_unary()
			left = bin_node(op, left, right)

		return left

	var fn parse_unary() Node:
		if (
			not self.bad
			and self.kind_now() == T_OP
			and (self.text_now() == "+" or self.text_now() == "-")
		):
			op := self.text_now()
			self.step()

			child := self.parse_unary()
			return un_node(op, child)

		return self.parse_power()

	var fn parse_power() Node:
		base := self.parse_primary()

		if not self.bad and self.kind_now() == T_OP and self.text_now() == "^":
			self.step()

			e := self.parse_power_operand()
			return bin_node("^", base, e)

		return base

	var fn parse_power_operand() Node:
		if (
			not self.bad
			and self.kind_now() == T_OP
			and (self.text_now() == "+" or self.text_now() == "-")
		):
			op := self.text_now()
			self.step()

			child := self.parse_power_operand()
			return un_node(op, child)

		return self.parse_power()

	var fn parse_primary() Node:
		if self.bad: return leaf(N_ERR, "#PARSE!")

		k := self.kind_now()

		if k == T_NUM:
			v := self.toks[self.pos].num
			g := self.toks[self.pos].good
			self.step()
			return Node(
				kind: N_NUM, text: "", num: v, flag: g, r1: no_ref(), r2: no_ref(),
				args: List[Node]()
			)

		if k == T_STR:
			s := self.text_now()
			self.step()
			return Node(
				kind: N_STR, text: s, num: 0.0, flag: false, r1: no_ref(), r2: no_ref(),
				args: List[Node]()
			)

		if k == T_ERR:
			self.step()
			return leaf(N_ERR, "#REF!")

		if k == T_REF:
			r := self.toks[self.pos].r1.clone()
			self.step()
			return Node(
				kind: N_REF, text: "", num: 0.0, flag: false, r1: r, r2: no_ref(),
				args: List[Node]()
			)

		if k == T_RANGE:
			a := self.toks[self.pos].r1.clone()
			b := self.toks[self.pos].r2.clone()
			self.step()
			return Node(
				kind: N_RANGE, text: "", num: 0.0, flag: false, r1: a, r2: b,
				args: List[Node]()
			)

		if k == T_IDENT:
			name := self.text_now().upper()
			self.step()

			if self.kind_now() == T_LP:
				self.step()

				var args = List[Node]()

				if self.kind_now() == T_RP:
					self.step()
					return Node(
						kind: N_CALL, text: name, num: 0.0, flag: false, r1: no_ref(),
						r2: no_ref(), args: args
					)

				var more = true

				while more:
					args.append(self.parse_expr())
					if self.bad: return leaf(N_ERR, "#PARSE!")

					if self.kind_now() == T_COMMA:
						self.step()
					else if self.kind_now() == T_RP:
						self.step()
						more = false
					else:
						self.bad = true
						return leaf(N_ERR, "#PARSE!")

				return Node(
					kind: N_CALL, text: name, num: 0.0, flag: false, r1: no_ref(),
					r2: no_ref(), args: args
				)

			if name == "TRUE":
				return Node(
					kind: N_BOOL, text: "", num: 0.0, flag: true, r1: no_ref(),
					r2: no_ref(), args: List[Node]()
				)
			if name == "FALSE":
				return Node(
					kind: N_BOOL, text: "", num: 0.0, flag: false, r1: no_ref(),
					r2: no_ref(), args: List[Node]()
				)

			return leaf(N_NAME, name)

		if k == T_LP:
			self.step()

			e := self.parse_expr()

			if self.kind_now() == T_RP:
				self.step()
				return e

			self.bad = true
			return e

		self.bad = true
		return leaf(N_ERR, "#PARSE!")

type Formula:
	root: Node
	good: Bool
	cells: List[Int]
	rects: List[Rect]

// Collects the cells named by valid single references and by ranges, outside
// ROW/COLUMN.
fn collect_refs(n: Node, var cells: List[Int], var rects: List[Rect]) Unit:
	if n.kind == N_REF:
		if n.r1.valid:
			cells.append(key_of(n.r1.col, n.r1.row))
		return

	if n.kind == N_RANGE:
		if n.r1.valid and n.r2.valid:
			rects.append(rect_of_refs(n.r1, n.r2))
		return

	if n.kind == N_CALL and (n.text == "ROW" or n.text == "COLUMN"): return

	for a in n.args:
		collect_refs(a, var cells, var rects)

fn make_formula(src: String) Formula:
	cs := src.chars()

	if toks := lex(cs):
		var p = Parser(toks: toks, pos: 0, bad: false)
		root := p.parse_expr()

		if not p.bad and p.kind_now() == T_END:
			var cells = List[Int]()
			var rects = List[Rect]()
			collect_refs(root, var cells, var rects)
			return Formula(root: root, good: true, cells: cells, rects: rects)

	return Formula(
		root: leaf(N_ERR, "#PARSE!"), good: false, cells: List[Int](),
		rects: List[Rect]()
	)

// ---------------------------------------------------------------- evaluation

fn eval(s: Sheet, n: Node) Value:
	k := n.kind

	if k == N_NUM:
		if n.flag: return Value.Num(n.num)
		return Value.Errv("#NUM!")

	if k == N_STR: return Value.Txt(n.text.clone())
	if k == N_BOOL: return Value.Flag(n.flag)
	if k == N_ERR: return Value.Errv(n.text.clone())

	if k == N_REF:
		if not n.r1.valid: return Value.Errv("#REF!")
		return s.vals[key_of(n.r1.col, n.r1.row)].clone()

	if k == N_RANGE: return Value.Errv("#VALUE!")
	if k == N_NAME: return Value.Errv("#NAME?")

	if k == N_UNARY:
		v := as_num(eval(s, n.args[0]))
		if is_err(v): return v
		if n.text == "-": return Value.Num(-num_val(v))

		return v

	if k == N_BIN: return eval_bin(s, n)
	if k == N_CALL: return call_fn(s, n)

	return Value.Errv("#PARSE!")

fn eval_bin(s: Sheet, n: Node) Value:
	va := eval(s, n.args[0])
	vb := eval(s, n.args[1])
	op := n.text.clone()

	if op == "&":
		if is_err(va): return va
		if is_err(vb): return vb

		return Value.Txt(display(va).concat(display(vb)))

	if is_cmp_op(op): return compare_op(op, va, vb)

	return arith(op, va, vb)

// Evaluates arguments that may be ranges into numbers. Empty on success, else the
// error.
fn gather_nums(s: Sheet, args: List[Node], var out: List[Float]) Value:
	for a in args:
		if a.kind == N_RANGE:
			if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")

			for k in range_keys(rect_of_refs(a.r1, a.r2)):
				v := s.vals[k].clone()
				if is_err(v): return v

				if is_num(v):
					out.append(num_val(v))
		else:
			c := as_num(eval(s, a))
			if is_err(c): return c

			out.append(num_val(c))

	return Value.Empty

// which: 0 SUM, 1 AVERAGE, 2 MIN, 3 MAX, 4 PRODUCT, 5 MEDIAN
fn agg(s: Sheet, args: List[Node], which: Int) Value:
	if args.is_empty(): return Value.Errv("#VALUE!")

	var xs = List[Float]()
	g := gather_nums(s, args, var xs)
	if is_err(g): return g

	n := xs.length()

	if which == 0:
		var t = 0.0
		for x in xs:
			t += x
		return finite(t)

	if which == 1:
		if n == 0: return Value.Errv("#DIV/0!")

		var t = 0.0
		for x in xs:
			t += x
		return finite(t / n.to_float())

	if which == 2 or which == 3:
		if n == 0: return Value.Num(0.0)

		var m = xs[0]

		for x in xs:
			if which == 2 and x < m:
				m = x
			if which == 3 and x > m:
				m = x

		return Value.Num(m)

	if which == 4:
		if n == 0: return Value.Num(0.0)

		var p = 1.0
		for x in xs:
			p *= x
		return finite(p)

	if n == 0: return Value.Errv("#NUM!")

	xs.sort()
	if n % 2 == 1: return finite(xs[n / 2])

	return finite((xs[n / 2 - 1] + xs[n / 2]) / 2.0)

// COUNT (nonempty_mode false) and COUNTA (true).
fn count_fn(s: Sheet, args: List[Node], nonempty_mode: Bool) Value:
	if args.is_empty(): return Value.Errv("#VALUE!")

	var c = 0

	for a in args:
		if a.kind == N_RANGE:
			if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")

			for k in range_keys(rect_of_refs(a.r1, a.r2)):
				v := s.vals[k].clone()

				if nonempty_mode:
					if not is_empty(v):
						c += 1
				else if is_num(v):
					c += 1
		else:
			v := eval(s, a)

			if nonempty_mode:
				if not is_empty(v):
					c += 1
			else if is_num(v):
				c += 1

	return Value.Num(c.to_float())

fn f_if(s: Sheet, args: List[Node]) Value:
	na := args.length()
	if na < 2 or na > 3: return Value.Errv("#VALUE!")

	c := as_flag(eval(s, args[0]))
	if is_err(c): return c
	if flag_val(c): return eval(s, args[1])
	if na == 3: return eval(s, args[2])

	return Value.Flag(false)

fn f_iferror(s: Sheet, args: List[Node]) Value:
	if args.length() != 2: return Value.Errv("#VALUE!")

	a := eval(s, args[0])
	if is_err(a): return eval(s, args[1])

	return a

fn to_int(f: Float) Int:
	if f > 1000000000.0: return 1000000000
	if f < -1000000000.0: return -1000000000

	return f.truncate_to_int().get(0)

fn f_choose(s: Sheet, args: List[Node]) Value:
	na := args.length()
	if na < 2: return Value.Errv("#VALUE!")

	iv := as_num(eval(s, args[0]))
	if is_err(iv): return iv

	idx := to_int(floor(num_val(iv)))
	if idx < 1 or idx > na - 1: return Value.Errv("#VALUE!")

	return eval(s, args[idx])

fn f_andor(s: Sheet, args: List[Node], is_and: Bool) Value:
	if args.is_empty(): return Value.Errv("#VALUE!")

	var any_part = false
	var all_true = true
	var any_true = false

	for a in args:
		if a.kind == N_RANGE:
			if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")

			for k in range_keys(rect_of_refs(a.r1, a.r2)):
				v := s.vals[k].clone()
				if is_err(v): return v
				if is_empty(v) or is_txt(v): continue

				t := flag_val(as_flag(v))
				any_part = true

				if not t:
					all_true = false
				else:
					any_true = true
		else:
			v := as_flag(eval(s, a))
			if is_err(v): return v

			t := flag_val(v)
			any_part = true

			if not t:
				all_true = false
			else:
				any_true = true

	if not any_part: return Value.Errv("#VALUE!")
	if is_and: return Value.Flag(all_true)

	return Value.Flag(any_true)

fn round_half_away(y: Float) Float:
	a := y.abs()
	t := truncate(a)
	r := if a - t >= 0.5: t + 1.0 else: t
	if y < 0.0: return -r

	return r

fn ascii_case(t: String, upper: Bool) String:
	var out = ""

	for c in t.chars():
		if upper and "abcdefghijklmnopqrstuvwxyz".contains(c):
			out = out.concat(c.upper())
		else if not upper and "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(c):
			out = out.concat(c.lower())
		else:
			out = out.concat(c)

	return out

// Returns the string form of a scalar argument, or the error it produced.
fn text_arg(s: Sheet, n: Node) Value:
	v := eval(s, n)
	if is_err(v): return v

	return Value.Txt(display(v))

fn f_mid_like(s: Sheet, args: List[Node], which: Int) Value:
	// which: 0 LEFT, 1 RIGHT
	na := args.length()
	if na < 1 or na > 2: return Value.Errv("#VALUE!")

	tv := text_arg(s, args[0])
	if is_err(tv): return tv

	t := txt_val(tv)
	var cnt = 1

	if na == 2:
		nv := as_num(eval(s, args[1]))
		if is_err(nv): return nv

		x := floor(num_val(nv))
		if x < 0.0: return Value.Errv("#VALUE!")

		cnt = to_int(x)

	if which == 0: return Value.Txt(t.take(cnt))

	len := t.scalar_length()
	var k = cnt
	if k > len:
		k = len
	return Value.Txt(t.drop(len - k))

fn f_rowcol(s: Sheet, args: List[Node], want_row: Bool) Value:
	if args.length() != 1: return Value.Errv("#VALUE!")

	a := args[0]

	if a.kind == N_REF:
		if not a.r1.valid: return Value.Errv("#REF!")
		if want_row: return Value.Num(a.r1.row.to_float())

		return Value.Num((a.r1.col + 1).to_float())

	if a.kind == N_RANGE:
		if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")
		if want_row: return Value.Num(a.r1.row.to_float())

		return Value.Num((a.r1.col + 1).to_float())

	return Value.Errv("#VALUE!")

fn f_index(s: Sheet, args: List[Node]) Value:
	na := args.length()
	if na < 2 or na > 3: return Value.Errv("#VALUE!")

	a := args[0]
	if a.kind != N_RANGE: return Value.Errv("#VALUE!")
	if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")

	rc := rect_of_refs(a.r1, a.r2)
	h := rc.r2 - rc.r1 + 1
	w := rc.c2 - rc.c1 + 1
	rv := as_num(eval(s, args[1]))
	if is_err(rv): return rv

	var row = 1
	var col = 1

	if na == 2:
		idx := to_int(floor(num_val(rv)))

		if h == 1:
			col = idx
		else:
			row = idx
	else:
		cv := as_num(eval(s, args[2]))
		if is_err(cv): return cv

		row = to_int(floor(num_val(rv)))
		col = to_int(floor(num_val(cv)))

	if row < 1 or row > h or col < 1 or col > w: return Value.Errv("#REF!")

	return s.vals[key_of(rc.c1 + col - 1, rc.r1 + row - 1)].clone()

fn f_countif(s: Sheet, args: List[Node]) Value:
	if args.length() != 2: return Value.Errv("#VALUE!")

	a := args[0]
	if a.kind != N_RANGE: return Value.Errv("#VALUE!")
	if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")

	cv := eval(s, args[1])
	if is_err(cv): return cv

	var op = "="
	var operand = cv.clone()

	if is_txt(cv):
		t := txt_val(cv)
		var oplen = 0

		if t.starts_with(">="):
			op = ">="
			oplen = 2
		else if t.starts_with("<="):
			op = "<="
			oplen = 2
		else if t.starts_with("<>"):
			op = "<>"
			oplen = 2
		else if t.starts_with(">"):
			op = ">"
			oplen = 1
		else if t.starts_with("<"):
			op = "<"
			oplen = 1
		else if t.starts_with("="):
			op = "="
			oplen = 1

		rest := t.drop(oplen)

		if f := parse_number_text(rest):
			operand = Value.Num(f)
		else:
			operand = Value.Txt(rest)

	var count = 0

	for k in range_keys(rect_of_refs(a.r1, a.r2)):
		v := s.vals[k].clone()

		if rank(v) == rank(operand):
			if op_holds(op, cmp_vals(v, operand)):
				count += 1
		else if op == "<>" and not is_empty(v):
			count += 1

	return Value.Num(count.to_float())

fn call_fn(s: Sheet, n: Node) Value:
	name := n.text.clone()
	args := n.args
	if name == "SUM": return agg(s, args, 0)
	if name == "AVERAGE": return agg(s, args, 1)
	if name == "MIN": return agg(s, args, 2)
	if name == "MAX": return agg(s, args, 3)
	if name == "PRODUCT": return agg(s, args, 4)
	if name == "MEDIAN": return agg(s, args, 5)
	if name == "COUNT": return count_fn(s, args, false)
	if name == "COUNTA": return count_fn(s, args, true)
	if name == "IF": return f_if(s, args)
	if name == "IFERROR": return f_iferror(s, args)
	if name == "CHOOSE": return f_choose(s, args)
	if name == "AND": return f_andor(s, args, true)
	if name == "OR": return f_andor(s, args, false)

	if name == "NOT":
		if args.length() != 1: return Value.Errv("#VALUE!")

		t := as_flag(eval(s, args[0]))
		if is_err(t): return t

		return Value.Flag(not flag_val(t))

	if name == "ABS" or name == "INT" or name == "SQRT":
		if args.length() != 1: return Value.Errv("#VALUE!")

		a := as_num(eval(s, args[0]))
		if is_err(a): return a

		x := num_val(a)
		if name == "ABS": return Value.Num(x.abs())
		if name == "INT": return finite(floor(x))
		if x < 0.0: return Value.Errv("#NUM!")

		return finite(sqrt(x))

	if name == "POW" or name == "MOD":
		if args.length() != 2: return Value.Errv("#VALUE!")

		a := as_num(eval(s, args[0]))
		if is_err(a): return a

		b := as_num(eval(s, args[1]))
		if is_err(b): return b

		x := num_val(a)
		y := num_val(b)
		if name == "POW": return finite(pow(x, y))
		if y == 0.0: return Value.Errv("#DIV/0!")

		return finite(x - y * floor(x / y))

	if name == "ROUND":
		na := args.length()
		if na < 1 or na > 2: return Value.Errv("#VALUE!")

		x := as_num(eval(s, args[0]))
		if is_err(x): return x

		var d = 0.0

		if na == 2:
			dv := as_num(eval(s, args[1]))
			if is_err(dv): return dv

			d = truncate(num_val(dv))

		if d.abs() > 15.0: return Value.Errv("#NUM!")

		p := pow(10.0, d)
		y := num_val(x) * p
		return finite(round_half_away(y) / p)

	if name == "LEN":
		if args.length() != 1: return Value.Errv("#VALUE!")

		tv := text_arg(s, args[0])
		if is_err(tv): return tv

		return Value.Num(txt_val(tv).scalar_length().to_float())

	if name == "UPPER" or name == "LOWER":
		if args.length() != 1: return Value.Errv("#VALUE!")

		tv := text_arg(s, args[0])
		if is_err(tv): return tv

		return Value.Txt(ascii_case(txt_val(tv), name == "UPPER"))

	if name == "TRIM":
		if args.length() != 1: return Value.Errv("#VALUE!")

		tv := text_arg(s, args[0])
		if is_err(tv): return tv

		return Value.Txt(txt_val(tv).fields().join(" "))

	if name == "LEFT": return f_mid_like(s, args, 0)
	if name == "RIGHT": return f_mid_like(s, args, 1)

	if name == "MID":
		if args.length() != 3: return Value.Errv("#VALUE!")

		tv := text_arg(s, args[0])
		if is_err(tv): return tv

		sv := as_num(eval(s, args[1]))
		if is_err(sv): return sv

		lv := as_num(eval(s, args[2]))
		if is_err(lv): return lv

		st := floor(num_val(sv))
		ln := floor(num_val(lv))
		if st < 1.0 or ln < 0.0: return Value.Errv("#VALUE!")

		return Value.Txt(txt_val(tv).drop(to_int(st) - 1).take(to_int(ln)))

	if name == "CONCAT":
		if args.is_empty(): return Value.Errv("#VALUE!")

		var buf = ""

		for a in args:
			if a.kind == N_RANGE:
				if not (a.r1.valid and a.r2.valid): return Value.Errv("#REF!")

				for k in range_keys(rect_of_refs(a.r1, a.r2)):
					v := s.vals[k].clone()
					if is_err(v): return v

					buf = buf.concat(display(v))
			else:
				v := eval(s, a)
				if is_err(v): return v

				buf = buf.concat(display(v))

		return Value.Txt(buf)

	if name == "SUBSTITUTE":
		if args.length() != 3: return Value.Errv("#VALUE!")

		sv := text_arg(s, args[0])
		if is_err(sv): return sv

		ov := text_arg(s, args[1])
		if is_err(ov): return ov

		nv := text_arg(s, args[2])
		if is_err(nv): return nv

		old := txt_val(ov)
		if old == "": return sv

		return Value.Txt(txt_val(sv).replace(old, txt_val(nv)))

	if name == "VALUE":
		if args.length() != 1: return Value.Errv("#VALUE!")
		return as_num(eval(s, args[0]))

	if name == "ISERROR" or name == "ISBLANK" or name == "ISNUMBER" or name == "ISTEXT":
		if args.length() != 1: return Value.Errv("#VALUE!")

		v := eval(s, args[0])
		if name == "ISERROR": return Value.Flag(is_err(v))
		if name == "ISBLANK": return Value.Flag(is_empty(v))
		if name == "ISNUMBER": return Value.Flag(is_num(v))

		return Value.Flag(is_txt(v))

	if name == "ROW": return f_rowcol(s, args, true)
	if name == "COLUMN": return f_rowcol(s, args, false)
	if name == "INDEX": return f_index(s, args)
	if name == "COUNTIF": return f_countif(s, args)

	return Value.Errv("#NAME?")

// Value a formula cell settles to: a formula result that is empty becomes 0.
fn compute(s: Sheet, k: Int) Value:
	if f := s.forms.get(k):
		if not f.good: return Value.Errv("#PARSE!")

		v := eval(s, f.root)
		if is_empty(v): return Value.Num(0.0)

		return v

	return Value.Empty

// ---------------------------------------------------------------- sheet state

type Sheet:
	raws: List[String]
	vals: List[Value]
	forms: Map[Int, Formula]
	evals: Int

fn new_sheet() Sheet:
	var raws = List[String](reserve: GRID)
	var vals = List[Value](reserve: GRID)

	for i in 0..GRID:
		raws.append("")
		vals.append(Value.Empty)

	return Sheet(raws: raws, vals: vals, forms: Map[Int, Formula](), evals: 0)

fn filled_int(n: Int, v: Int) List[Int]:
	var out = List[Int]()
	for i in 0..n:
		out.append(v)
	return out

fn filled_bool(n: Int, v: Bool) List[Bool]:
	var out = List[Bool]()
	for i in 0..n:
		out.append(v)
	return out

// Tarjan's strongly connected components over the affected formulas. Edges are linked
// lists: head[v] is the first edge out of v, nxt[e] the next, to[e] its target.
type Scc:
	head: List[Int]
	nxt: List[Int]
	to: List[Int]
	index: List[Int]
	low: List[Int]
	on: List[Bool]
	stack: List[Int]
	counter: Int
	cyc: List[Bool]

impl Scc:
	var fn visit(v: Int) Unit:
		self.index.replace(v, self.counter)
		self.low.replace(v, self.counter)
		self.counter += 1
		self.stack.append(v)
		self.on.replace(v, true)

		var e = self.head[v]

		while e >= 0:
			w := self.to[e]
			e = self.nxt[e]
			if w == v:
				self.cyc.replace(v, true)

			if self.index[w] < 0:
				self.visit(w)
				if self.low[w] < self.low[v]:
					self.low.replace(v, self.low[w])
			else if self.on[w]:
				if self.index[w] < self.low[v]:
					self.low.replace(v, self.index[w])

		if self.low[v] == self.index[v]:
			var members = List[Int]()
			var go = true

			while go:
				top := self.stack.length() - 1
				x := self.stack[top]
				self.stack.remove(top)
				self.on.replace(x, false)
				members.append(x)
				if x == v:
					go = false

			if members.length() > 1:
				for x in members:
					self.cyc.replace(x, true)

impl Sheet:
	var fn put(k: Int, raw: String) Unit:
		self.raws.replace(k, raw.clone())

		if raw == "":
			self.vals.replace(k, Value.Empty)
			self.forms.remove(k)
		else if raw.starts_with("="):
			self.forms.remove(k)
			self.forms.add(k, make_formula(raw.drop(1)))
			self.vals.replace(k, Value.Empty)
		else:
			self.forms.remove(k)
			self.vals.replace(k, classify(raw))

	// Recalculates the formulas affected by the changed cells; returns how many.
	var fn recalc(changed: List[Int]) Int:
		idx := build_index(self)
		aff := closure(idx, changed, true)
		m := aff.length()
		if m == 0: return 0

		var pos = filled_int(GRID, -1)
		for i in 0..m:
			pos.replace(aff[i], i)

		// Edge p -> i when affected formula p is a precedent of affected formula i.
		var shead = filled_int(m, -1)
		var snx = List[Int]()
		var sto = List[Int]()

		for i in 0..m:
			if f := self.forms.get(aff[i]):
				for c in f.cells:
					p := pos[c]

					if p >= 0:
						sto.append(i)
						snx.append(shead[p])
						shead.replace(p, sto.length() - 1)

				for rc in f.rects:
					for t in 0..m:
						if rect_has(rc, aff[t]):
							sto.append(i)
							snx.append(shead[t])
							shead.replace(t, sto.length() - 1)

		var scc = Scc(
			head: shead, nxt: snx, to: sto, index: filled_int(m, -1),
			low: filled_int(m, 0), on: filled_bool(m, false), stack: List[Int](),
			counter: 0, cyc: filled_bool(m, false)
		)
		for i in 0..m:
			if scc.index[i] < 0:
				scc.visit(i)

		var indeg = filled_int(m, 0)

		for i in 0..m:
			if scc.cyc[i]:
				self.vals.replace(aff[i], Value.Errv("#CYCLE!"))
			else:
				var e = scc.head[i]

				while e >= 0:
					d := scc.to[e]
					if not scc.cyc[d]:
						indeg.replace(d, indeg[d] + 1)
					e = scc.nxt[e]

		var ready = List[Int]()
		for i in 0..m:
			if not scc.cyc[i] and indeg[i] == 0:
				ready.append(i)

		var rq = 0

		while rq < ready.length():
			i := ready[rq]
			rq += 1

			v := compute(self, aff[i])
			self.vals.replace(aff[i], v)

			var e = scc.head[i]

			while e >= 0:
				d := scc.to[e]

				if not scc.cyc[d]:
					indeg.replace(d, indeg[d] - 1)
					if indeg[d] == 0:
						ready.append(d)

				e = scc.nxt[e]

		self.evals += m
		return m

// ---------------------------------------------------------------- dependencies

// Reverse dependency index over the formulas of a sheet, built once per command.
type DepIndex:
	fkeys: List[Int]
	fidx: List[Int]
	ehead: List[Int]
	enext: List[Int]
	efor: List[Int]
	rfor: List[Int]
	rrect: List[Rect]

fn build_index(sh: Sheet) DepIndex:
	var fkeys = List[Int]()
	var fidx = filled_int(GRID, -1)
	var ehead = filled_int(GRID, -1)
	var enext = List[Int]()
	var efor = List[Int]()
	var rfor = List[Int]()
	var rrect = List[Rect]()

	for k in sh.forms.keys():
		if f := sh.forms.get(k):
			fi := fkeys.length()
			fkeys.append(k)
			fidx.replace(k, fi)

			for c in f.cells:
				efor.append(fi)
				enext.append(ehead[c])
				ehead.replace(c, efor.length() - 1)

			for rc in f.rects:
				rfor.append(fi)
				rrect.append(rc.clone())

	return DepIndex(
		fkeys: fkeys, fidx: fidx, ehead: ehead, enext: enext, efor: efor, rfor: rfor,
		rrect: rrect
	)

// Formula cell keys that depend on the start cells, directly or transitively, in
// discovery order. With seed, a formula among the start cells is itself included (it is
// affected by its own change).
fn closure(idx: DepIndex, start: List[Int], seed: Bool) List[Int]:
	var seen = filled_bool(idx.fkeys.length(), false)
	var out = List[Int]()
	var q = List[Int]()

	for k in start:
		q.append(k)

		fi := idx.fidx[k]

		if seed and fi >= 0 and not seen[fi]:
			seen.replace(fi, true)
			out.append(k)

	var qi = 0

	while qi < q.length():
		node := q[qi]
		qi += 1

		var e = idx.ehead[node]

		while e >= 0:
			fi := idx.efor[e]
			e = idx.enext[e]

			if not seen[fi]:
				seen.replace(fi, true)
				out.append(idx.fkeys[fi])
				q.append(idx.fkeys[fi])

		for r in 0..idx.rrect.length():
			if rect_has(idx.rrect[r], node):
				fi := idx.rfor[r]

				if not seen[fi]:
					seen.replace(fi, true)
					out.append(idx.fkeys[fi])
					q.append(idx.fkeys[fi])

	return out

// Cells that the formula at k refers to, ascending by key (row, then column).
fn precedents_of(sh: Sheet, k: Int) List[Int]:
	var mark = filled_bool(GRID, false)

	if f := sh.forms.get(k):
		for c in f.cells:
			mark.replace(c, true)
		for rc in f.rects:
			for kk in range_keys(rc):
				mark.replace(kk, true)

	var out = List[Int]()
	for i in 0..GRID:
		if mark[i]:
			out.append(i)
	return out

// Formulas that depend on k, directly or transitively, ascending by key.
fn dependents_of(sh: Sheet, k: Int) List[Int]:
	idx := build_index(sh)
	var mark = filled_bool(GRID, false)
	for f in closure(idx, [k], false):
		mark.replace(f, true)

	var out = List[Int]()
	for i in 0..GRID:
		if mark[i]:
			out.append(i)
	return out

fn names_line(ks: List[Int]) String:
	if ks.is_empty(): return "(none)"

	var out = ""

	for k in ks:
		if out != "":
			out = out.concat(" ")
		out = out.concat(name_of(k))

	return out

// ---------------------------------------------------------------- shifting (copy)

fn shifted_ref(r: Ref, dc: Int, dr: Int) Ref?:
	var c = r.col
	var w = r.row
	if not r.abs_col:
		c = r.col + dc
	if not r.abs_row:
		w = r.row + dr
	if c < 0 or c > 25 or w < 1 or w > 999: return none

	return Ref(col: c, row: w, valid: true, abs_col: r.abs_col, abs_row: r.abs_row)

fn ref_text(r: Ref) String:
	var s = ""
	if r.abs_col:
		s = "$"
	s = s.concat(col_name(r.col))
	if r.abs_row:
		s = s.concat("$")
	return s.concat("{r.row}")

fn shift_token(t: Tok, cs: List[String], dc: Int, dr: Int) String:
	if t.kind == T_REF:
		if not t.r1.valid: return slice_chars(cs, t.start, t.stop)
		if nr := shifted_ref(t.r1, dc, dr): return ref_text(nr)

		return "#REF!"

	if not (t.r1.valid and t.r2.valid): return slice_chars(cs, t.start, t.stop)

	if a := shifted_ref(t.r1, dc, dr):
		if b := shifted_ref(t.r2, dc, dr): return "{ref_text(a)}:{ref_text(b)}"
	return "#REF!"

// Shifts the references of a formula source by (dc, dr); unchanged if it cannot be
// tokenized.
fn shift_source(src: String, dc: Int, dr: Int) String:
	cs := src.chars()

	if toks := lex(cs):
		var out = ""
		var pos = 0

		for t in toks:
			if t.kind == T_REF or t.kind == T_RANGE:
				out = out.concat(slice_chars(cs, pos, t.start))
				out = out.concat(shift_token(t, cs, dc, dr))
				pos = t.stop

		out = out.concat(slice_chars(cs, pos, cs.length()))
		return out

	return src.clone()

// ---------------------------------------------------------------- import (CSV)

// Records of the block: quoted sections, doubled quotes, blank records skipped.
fn csv_records(block: List[String]) List[List[String]]:
	cs := block.join("\n").chars()
	n := cs.length()
	var recs = List[List[String]]()
	var fields = List[String]()
	var field = ""
	var inq = false
	var started = false
	var i = 0

	while i < n:
		c := ch(cs, i)

		if inq:
			if c == 34:
				if ch(cs, i + 1) == 34:
					field = field.concat("\"")
					i += 1
				else:
					inq = false
			else:
				field = field.concat(cs[i])

			started = true
		else if c == 34:
			inq = true
			started = true
		else if c == 44:
			fields.append(field)
			field = ""
			started = true
		else if c == 10:
			if started:
				fields.append(field)
				recs.append(fields)

			fields = List[String]()
			field = ""
			started = false
		else if c != 13:
			field = field.concat(cs[i])
			started = true

		i += 1

	if started:
		fields.append(field)
		recs.append(fields)

	return recs

// ---------------------------------------------------------------- output helpers

fn print_rect(sh: Sheet, rc: Rect) Unit:
	var r = rc.r1

	while r <= rc.r2:
		var line = ""
		var c = rc.c1

		while c <= rc.c2:
			if c > rc.c1:
				line = line.concat(" | ")
			line = line.concat(display(sh.vals[key_of(c, r)]))
			c += 1

		print(line)
		r += 1

fn csv_field(t: String) String:
	if (
		t.contains(",")
		or t.contains("\"")
		or t.contains("\n")
		or t.contains("\r")
		or t.starts_with(" ")
		or t.ends_with(" ")
	):
		return "\"{t.replace("\"", "\"\"")}\""
	return t.clone()

fn export_rect(sh: Sheet, rc: Rect, formulas: Bool) Unit:
	var r = rc.r1

	while r <= rc.r2:
		var line = ""
		var c = rc.c1

		while c <= rc.c2:
			if c > rc.c1:
				line = line.concat(",")

			k := key_of(c, r)

			if formulas:
				line = line.concat(csv_field(sh.raws[k]))
			else:
				line = line.concat(csv_field(display(sh.vals[k])))

			c += 1

		print(line)
		r += 1

// Bounding rectangle of the non-empty cells, or none for an empty sheet.
fn used_rect(sh: Sheet) Rect?:
	var any = false
	var maxc = 0
	var maxr = 1

	for k in 0..GRID:
		if sh.raws[k] != "":
			any = true
			if key_col(k) > maxc:
				maxc = key_col(k)
			if key_row(k) > maxr:
				maxr = key_row(k)

	if not any: return none

	return Rect(c1: 0, r1: 1, c2: maxc, r2: maxr)

fn bad_cell(t: String) Unit:
	print("error: bad cell reference '{t}'")

fn bad_range(t: String) Unit:
	print("error: bad range '{t}'")

// ---------------------------------------------------------------- commands

// Splits a line into whitespace-separated words.
fn words(line: String) List[String]:
	cs := line.chars()
	var out = List[String]()
	var i = 0

	while i < cs.length():
		while i < cs.length() and is_ws(ch(cs, i)):
			i += 1
		if i >= cs.length(): break

		var j = i
		while j < cs.length() and not is_ws(ch(cs, j)):
			j += 1
		out.append(slice_chars(cs, i, j))
		i = j

	return out

// Text after the first `count` words, with the ends trimmed.
fn rest_after(line: String, count: Int) String:
	cs := line.chars()
	var i = 0

	for w in 0..count:
		while i < cs.length() and is_ws(ch(cs, i)):
			i += 1
		while i < cs.length() and not is_ws(ch(cs, i)):
			i += 1

	return slice_chars(cs, i, cs.length()).trim()

fn do_import(var sh: Sheet, ws: List[String], block: List[String]) Unit:
	if ws.length() != 2:
		print("error: usage: import CELL")
		return

	k0 := cell_or_neg(ws[1])

	if k0 < 0:
		bad_cell(ws[1])
		return

	recs := csv_records(block)
	rows := recs.length()
	var cols = 0
	for rec in recs:
		if rec.length() > cols:
			cols = rec.length()

	c0 := key_col(k0)
	r0 := key_row(k0)

	if c0 + cols > COLS or r0 - 1 + rows > 999:
		print("error: import out of range")
		return

	var changed = List[Int]()
	var ri = 0

	for rec in recs:
		var ci = 0

		for f in rec:
			k := key_of(c0 + ci, r0 + ri)
			sh.put(k, f.trim())
			changed.append(k)
			ci += 1

		ri += 1

	m := sh.recalc(changed)
	print("imported {rows} rows, {cols} columns; recalc {m}")

fn do_copy(var sh: Sheet, ws: List[String]) Unit:
	if ws.length() != 3:
		print("error: usage: copy SRC DST")
		return

	sk := cell_or_neg(ws[1])

	if sk < 0:
		bad_cell(ws[1])
		return

	if rc := range_arg(ws[2]):
		src_raw := sh.raws[sk].clone()
		sc := key_col(sk)
		sr := key_row(sk)
		var changed = List[Int]()

		for dk in range_keys(rc):
			dc := key_col(dk) - sc
			dr := key_row(dk) - sr
			var newraw = ""

			if src_raw == "":
				newraw = ""
			else if src_raw.starts_with("="):
				newraw = "=".concat(shift_source(src_raw.drop(1), dc, dr))
			else:
				newraw = src_raw.clone()

			sh.put(dk, newraw)
			changed.append(dk)

		m := sh.recalc(changed)
		print("recalc {m}")
		return

	bad_range(ws[2])

fn do_print(sh: Sheet, ws: List[String]) Unit:
	n := ws.length()

	if n > 2:
		print("error: usage: print [RANGE]")
		return

	var rng = ""

	if n == 2:
		if ws[1] == "formulas":
			print("error: usage: print [RANGE]")
			return

		rng = ws[1].clone()

	if rng == "":
		if u := used_rect(sh):
			print_rect(sh, u)
		else:
			print("(empty sheet)")

		return

	if rc := range_arg(rng):
		print_rect(sh, rc)
		return

	bad_range(rng)

fn do_export(sh: Sheet, ws: List[String]) Unit:
	n := ws.length()

	if n > 3:
		print("error: usage: export [formulas] [RANGE]")
		return

	var formulas = false
	var rng = ""

	if n == 2:
		if ws[1] == "formulas":
			formulas = true
		else if ws[1] != "values":
			rng = ws[1].clone()

	if n == 3:
		if ws[1] != "formulas" and ws[1] != "values":
			print("error: usage: export [formulas] [RANGE]")
			return

		formulas = ws[1] == "formulas"
		rng = ws[2].clone()

	if rng == "":
		if u := used_rect(sh):
			export_rect(sh, u, formulas)
		else:
			print("(empty sheet)")

		return

	if rc := range_arg(rng):
		export_rect(sh, rc, formulas)
		return

	bad_range(rng)

fn exec(var sh: Sheet, line: String) Unit:
	ws := words(line)
	cmd := ws[0]
	n := ws.length()

	if cmd == "set":
		if n < 2:
			print("error: usage: set CELL VALUE")
			return

		k := cell_or_neg(ws[1])

		if k < 0:
			bad_cell(ws[1])
			return

		sh.put(k, rest_after(line, 2))

		m := sh.recalc([k])
		print("recalc {m}")
		return

	if cmd == "clear":
		if n != 2:
			print("error: usage: clear CELL")
			return

		k := cell_or_neg(ws[1])

		if k < 0:
			bad_cell(ws[1])
			return

		sh.put(k, "")

		m := sh.recalc([k])
		print("recalc {m}")
		return

	if cmd == "get":
		if n != 2:
			print("error: usage: get CELL")
			return

		k := cell_or_neg(ws[1])

		if k < 0:
			bad_cell(ws[1])
			return

		if sh.raws[k] == "":
			print("(empty)")
		else:
			print(display(sh.vals[k]))

		return

	if cmd == "show":
		if n != 2:
			print("error: usage: show CELL")
			return

		k := cell_or_neg(ws[1])

		if k < 0:
			bad_cell(ws[1])
			return

		name := name_of(k)

		if sh.raws[k] == "":
			print("{name}: (empty)")
		else if sh.forms.contains(k):
			print("{name}: {sh.raws[k]} => {display(sh.vals[k])}")
		else:
			print("{name}: {sh.raws[k]}")

		return

	if cmd == "precedents" or cmd == "dependents":
		if n != 2:
			print("error: usage: {cmd} CELL")
			return

		k := cell_or_neg(ws[1])

		if k < 0:
			bad_cell(ws[1])
			return

		if cmd == "precedents":
			print(names_line(precedents_of(sh, k)))
		else:
			print(names_line(dependents_of(sh, k)))

		return

	if cmd == "copy":
		do_copy(var sh, ws)
		return

	if cmd == "print":
		do_print(sh, ws)
		return

	if cmd == "export":
		do_export(sh, ws)
		return

	if cmd == "stats":
		var nonempty = 0
		for k in 0..GRID:
			if sh.raws[k] != "":
				nonempty += 1
		print("cells {nonempty} formulas {sh.forms.length()} evals {sh.evals}")
		return

	print("error: unknown command '{cmd}'")

fn gather() Result[List[String], Error]:
	var all = List[String]()
	for line in lines(stdin()):
		all.append(line)
	return ok(all)

export fn main() Int:
	all := gather().get(List[String]())
	var sh = new_sheet()
	var i = 0

	while i < all.length():
		line := all[i].clone()
		i += 1

		t := line.trim()
		if t == "" or t.starts_with("#"): continue

		print("> {line.trim_end()}")

		ws := words(line)

		if ws[0] == "import":
			var block = List[String]()

			while i < all.length() and all[i] != ".":
				block.append(all[i].clone())
				i += 1

			if i < all.length():
				i += 1
			do_import(var sh, ws, block)
			continue

		exec(var sh, line)

	return 0
