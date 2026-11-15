import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type P:
	cs: List[String]
	pos: Int = 0
	bad: Bool = false
	dz: Bool = false

fn var P.skip() Unit:
	while self.pos < self.cs.length():
		c := self.cs.get(self.pos, "")
		if c == " " or c == "\t":
			self.pos += 1
		else:
			return

fn var P.peek() String:
	self.skip()
	return self.cs.get(self.pos, "")

fn var P.atom() Int:
	c := self.peek()
	if c == "-":
		self.pos += 1
		return 0 - self.atom()
	if c == "(":
		self.pos += 1
		v := self.expr()
		if self.peek() == ")":
			self.pos += 1
		else:
			self.bad = true
		return v
	d := c.parse_int()
	if c.length() == 1 and d.is_some():
		var n = 0
		while self.pos < self.cs.length():
			x := self.cs.get(self.pos, "")
			dd := x.parse_int()
			if x.length() == 1 and dd.is_some() and x != "-" and x != "+":
				n = n * 10 + dd.get(0)
				self.pos += 1
			else:
				break
		return n
	self.bad = true
	return 0

fn var P.term() Int:
	var v = self.atom()
	while true:
		c := self.peek()
		if c == "*":
			self.pos += 1
			v = v * self.atom()
		else if c == "/":
			self.pos += 1
			r := self.atom()
			if r == 0:
				self.dz = true
			else:
				v = v / r
		else:
			break
	return v

fn var P.expr() Int:
	var v = self.term()
	while true:
		c := self.peek()
		if c == "+":
			self.pos += 1
			v = v + self.term()
		else if c == "-":
			self.pos += 1
			v = v - self.term()
		else:
			break
	return v

fn eval(line: String) String:
	var p = P(line.clone().chars())
	v := p.expr()
	if p.peek() != "":
		p.bad = true
	if p.bad: return "error: syntax"
	if p.dz: return "error: division by zero"
	return "{v}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(eval(line))
