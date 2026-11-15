import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type P:
	toks: List[String]
	pos: Int = 0
	bad: Bool = false
	dz: Bool = false

fn is_digit(c: String) Bool: c >= "0" and c <= "9"

fn tokenize(s: String) List[String]:
	var out = List[String]()
	var cur = ""
	for c in s.chars():
		if is_digit(c):
			cur = cur + c
			continue
		if cur != "":
			out.append(cur.clone())
			cur = ""
		if c == " " or c == "\t" or c == "\r": continue
		out.append(c.clone())
	if cur != "": out.append(cur.clone())
	return out

fn var P.peek() String:
	return self.toks.get(self.pos, "")

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
	if is_digit(t.slice(0, 1).get("")):
		self.pos += 1
		return t.parse_int().get(0)
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
				self.dz = true
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

fn eval(line: String) String:
	var p = P(tokenize(line))
	v := p.expr()
	if p.bad or p.pos < p.toks.length(): return "error: syntax"
	if p.dz: return "error: division by zero"
	return "{v}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim_chars(" \t\r") == "": continue
		print(eval(line))
