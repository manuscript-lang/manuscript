import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type P:
	toks: List[String] = []
	pos: Int = 0
	div0: Bool = false
	bad: Bool = false

fn P.peek() String:
	if self.pos < self.toks.length():
		return self.toks.get(self.pos, "")
	return ""

fn var P.primary() Int:
	t := self.peek()
	if t == "":
		self.bad = true
		return 0
	if t == "-":
		self.pos += 1
		return 0 - self.primary()
	if t == "(":
		self.pos += 1
		v := self.expr()
		if self.peek() != ")":
			self.bad = true
			return 0
		self.pos += 1
		return v
	if v := t.parse_int():
		self.pos += 1
		return v
	self.bad = true
	return 0

fn var P.term() Int:
	var v = self.primary()
	while not self.bad:
		t := self.peek()
		if t == "*":
			self.pos += 1
			v = v * self.primary()
		else if t == "/":
			self.pos += 1
			d := self.primary()
			if d == 0:
				self.div0 = true
				v = 0
			else:
				v = v / d
		else:
			break
	return v

fn var P.expr() Int:
	var v = self.term()
	while not self.bad:
		t := self.peek()
		if t == "+":
			self.pos += 1
			v = v + self.term()
		else if t == "-":
			self.pos += 1
			v = v - self.term()
		else:
			break
	return v

fn is_digit(c: String) Bool:
	return c >= "0" and c <= "9"

fn tokenize(line: String) List[String]?:
	var out: List[String] = []
	var num = ""
	for c in line.chars():
		if is_digit(c):
			num = num + c
			continue
		if num != "":
			out.append(num.clone())
			num = ""
		if c == " " or c == "\t" or c == "\r":
			continue
		if c == "+" or c == "-" or c == "*" or c == "/" or c == "(" or c == ")":
			out.append(c.clone())
		else:
			return none
	if num != "":
		out.append(num.clone())
	return out

fn eval_line(line: String) String:
	t := tokenize(line)
	if t.is_none():
		return "error: syntax"
	var p = P(toks: t.get([]))
	v := p.expr()
	if p.bad or p.pos < p.toks.length():
		return "error: syntax"
	if p.div0:
		return "error: division by zero"
	return "{v}"

// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim_chars(" \t\r") == "":
			continue
		print(eval_line(line))
