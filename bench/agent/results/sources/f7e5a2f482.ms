import (
	stdin, stdout from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
)

// Token: kind is "n" (number, value in val), an operator or parenthesis
// ("+", "-", "*", "/", "(", ")"), or "?" for an unknown character.
type Tok:
	kind: String
	val: Int

// Parse result. ok is false on a syntax error. dz records that a division by
// zero was evaluated somewhere (evaluation continues with 0 so every division
// is still checked and syntax errors take priority).
type R:
	v: Int
	pos: Int
	ok: Bool
	dz: Bool

fn bad() R:
	return R(v: 0, pos: 0, ok: false, dz: false)

fn digit_value(c: String) Int:
	var i = 0

	for d in "0123456789".chars():
		if d == c: return i

		i += 1

	return -1

fn tokenize(line: String) List[Tok]:
	var out = List[Tok]()
	var in_num = false
	var cur = 0

	for c in line.chars():
		d := digit_value(c)

		if d >= 0:
			if in_num:
				cur = cur * 10 + d
			else:
				in_num = true
				cur = d
		else:
			if in_num:
				out.append(Tok(kind: "n", val: cur))
				in_num = false
				cur = 0

			if c == "+" or c == "-" or c == "*" or c == "/" or c == "(" or c == ")":
				out.append(Tok(kind: c, val: 0))
			else if c != " " and c != "\t":
				out.append(Tok(kind: "?", val: 0))

	if in_num:
		out.append(Tok(kind: "n", val: cur))
	return out

fn parse_primary(toks: List[Tok], pos: Int) R:
	if pos >= toks.length(): return bad()

	t := toks[pos]
	if t.kind == "n": return R(v: t.val, pos: pos + 1, ok: true, dz: false)

	if t.kind == "(":
		r := parse_expr(toks, pos + 1)
		if not r.ok: return r
		if r.pos < toks.length() and toks[r.pos].kind == ")":
			return R(v: r.v, pos: r.pos + 1, ok: true, dz: r.dz)

		return bad()

	return bad()

fn parse_unary(toks: List[Tok], pos: Int) R:
	if pos < toks.length() and toks[pos].kind == "-":
		r := parse_unary(toks, pos + 1)
		if not r.ok: return r

		return R(v: 0 - r.v, pos: r.pos, ok: true, dz: r.dz)

	return parse_primary(toks, pos)

fn parse_term(toks: List[Tok], pos: Int) R:
	first := parse_unary(toks, pos)
	if not first.ok: return first

	var v = first.v
	var p = first.pos
	var dz = first.dz

	while p < toks.length() and (toks[p].kind == "*" or toks[p].kind == "/"):
		is_mul := toks[p].kind == "*"
		r := parse_unary(toks, p + 1)
		if not r.ok: return r

		dz = dz or r.dz

		if is_mul:
			v *= r.v
		else if r.v == 0:
			dz = true
			v = 0
		else:
			v /= r.v

		p = r.pos

	return R(v: v, pos: p, ok: true, dz: dz)

fn parse_expr(toks: List[Tok], pos: Int) R:
	first := parse_term(toks, pos)
	if not first.ok: return first

	var v = first.v
	var p = first.pos
	var dz = first.dz

	while p < toks.length() and (toks[p].kind == "+" or toks[p].kind == "-"):
		is_add := toks[p].kind == "+"
		r := parse_term(toks, p + 1)
		if not r.ok: return r

		dz = dz or r.dz

		if is_add:
			v += r.v
		else:
			v -= r.v

		p = r.pos

	return R(v: v, pos: p, ok: true, dz: dz)

fn evaluate(line: String) String:
	toks := tokenize(line)
	if toks.is_empty(): return ""

	r := parse_expr(toks, 0)
	if not r.ok or r.pos != toks.length(): return "error: syntax"
	if r.dz: return "error: division by zero"

	return "{r.v}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn process() Int!:
	var out = stdout()

	for line in lines(stdin()):
		s := evaluate(line)
		if s != "":
			try out.write("{s}\n")

	try out.flush()
	return ok(0)

export fn main() Int:
	return process().get(1)
