// A tokenizer, recursive-descent parser and evaluator for arithmetic: strings, enums
// with payloads, recursive values.
import StringBuilder from "@std/string_builder.ms"

enum Tok:
	Num(v: Int)
	Sym(c: Int)

enum Expr:
	Lit(v: Int)
	Bin(op: Int, left: Expr, right: Expr)

type Parser:
	toks: List[Tok]
	pos: Int = 0

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn gen(depth: Int, var x: Int, var out: StringBuilder) Unit:
	x = lcg(x)

	if depth == 0 or x % 5 == 0:
		out.append("{x / 7 % 100}")
		return

	x = lcg(x)

	op := ["+", "-", "*", "%"][x / 3 % 4]
	out.append("(")
	gen(depth - 1, var x, var out)
	out.append(" {op} ")
	gen(depth - 1, var x, var out)
	out.append(")")

fn tokenize(text: String) List[Tok]:
	var toks: List[Tok] = []
	n := text.length()
	var i = 0

	while i < n:
		c := text.scalar_at(i)

		if c >= 48 and c <= 57:
			var v = 0

			while i < n and text.scalar_at(i) >= 48 and text.scalar_at(i) <= 57:
				v = v * 10 + text.scalar_at(i) - 48
				i += 1

			toks.append(Tok.Num(v))
		else if c == 32:
			i += 1
		else:
			toks.append(Tok.Sym(c))
			i += 1

	return toks

fn symbol(t: Tok) Int:
	match t:
		Sym(c): return c
		Num(_): return 0

fn var Parser.expr() Expr:
	match self.toks[self.pos]:
		Num(v):
			self.pos += 1
			return Expr.Lit(v)
		Sym(_):
			self.pos += 1  // "("

			left := self.expr()
			op := symbol(self.toks[self.pos])
			self.pos += 1

			right := self.expr()
			self.pos += 1  // ")"
			return Expr.Bin(op, left, right)

fn eval(e: Expr) Int:
	match e:
		Lit(v): return v
		Bin(op, l, r):
			a := eval(l)
			b := eval(r)
			if op == 43: return (a + b) % 1000003
			if op == 45: return (a - b) % 1000003
			if op == 42: return a * b % 1000003

			return if b == 0: a else: a % b

fn main() Unit:
	var x = 3
	var total = 0
	var tokens = 0
	var chars = 0

	for i in 0..60000:
		var sb = StringBuilder()
		gen(9, var x, var sb)

		text := sb.build()
		chars += text.length()

		toks := tokenize(text)
		tokens += toks.length()

		var p = Parser(toks)
		total = (total + eval(p.expr())) % 1000003

	print("chars {chars} tokens {tokens} total {total}")
