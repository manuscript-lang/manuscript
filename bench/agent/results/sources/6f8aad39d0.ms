import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

type P:
	toks: List[String] = []
	pos: Int = 0
	bad: Bool = false
	dz: Bool = false

fn P.peek() String:
	if self.pos < self.toks.length():
		return self.toks[self.pos].clone()
	return ""

fn var P.factor() Int:
	t := self.peek()
	if t == "-":
		self.pos += 1
		return 0 - self.factor()
	if t == "(":
		self.pos += 1
		v := self.expr()
		if self.peek() == ")":
			self.pos += 1
		else:
			self.bad = true
		return v
	if t.length() > 0 and t >= "0" and t <= "9":
		self.pos += 1
		return t.parse_int().get(0)
	self.bad = true
	return 0

fn var P.term() Int:
	var v = self.factor()
	while self.peek() == "*" or self.peek() == "/":
		op := self.peek()
		self.pos += 1
		r := self.factor()
		if op == "*":
			v = v * r
		else if r == 0:
			self.dz = true
			v = 0
		else:
			v = v / r
	return v

fn var P.expr() Int:
	var v = self.term()
	while self.peek() == "+" or self.peek() == "-":
		op := self.peek()
		self.pos += 1
		r := self.term()
		if op == "+":
			v = v + r
		else:
			v = v - r
	return v

fn tokenize(line: String) List[String]?:
	var out: List[String] = []
	var num = ""
	for c in line.chars():
		if c >= "0" and c <= "9":
			num = num + c
			continue
		if num.length() > 0:
			out.append(num.clone())
			num = ""
		if c == " " or c == "\t" or c == "\r":
			continue
		if c == "+" or c == "-" or c == "*" or c == "/" or c == "(" or c == ")":
			out.append(c.clone())
		else:
			return none
	if num.length() > 0:
		out.append(num.clone())
	return out

fn eval(line: String) String:
	t := tokenize(line)
	if t.is_none():
		return "error: syntax"
	var p = P(toks: t.get([]))
	v := p.expr()
	if p.bad or p.pos < p.toks.length():
		return "error: syntax"
	if p.dz:
		return "error: division by zero"
	return "{v}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim_chars(" \t\r").length() == 0:
			continue
		print(eval(line))
