import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Parser:
	cs: List[String]
	pos: Int = 0
	bad: Bool = false
	dz: Bool = false

fn Parser.raw() String: self.cs.get(self.pos, "")

fn var Parser.peek() String:
	while self.raw() == " " or self.raw() == "\t" or self.raw() == "\r":
		self.pos += 1
	return self.raw()

fn var Parser.atom() Int:
	c := self.peek()
	if c == "(":
		self.pos += 1
		v := self.expr()
		if self.peek() == ")":
			self.pos += 1
		else:
			self.bad = true
		return v
	if c == "-":
		self.pos += 1
		return 0 - self.atom()
	if c != "" and "0123456789".contains(c):
		var n = 0
		while self.raw() != "" and "0123456789".contains(self.raw()):
			n = n * 10 + self.raw().parse_int().get(0)
			self.pos += 1
		return n
	self.bad = true
	return 0

fn var Parser.term() Int:
	var v = self.atom()
	while not self.bad and (self.peek() == "*" or self.peek() == "/"):
		op := self.peek()
		self.pos += 1
		r := self.atom()
		if op == "*":
			v = v * r
		else if r == 0:
			self.dz = true
			v = 0
		else:
			v = v / r
	return v

fn var Parser.expr() Int:
	var v = self.term()
	while not self.bad and (self.peek() == "+" or self.peek() == "-"):
		op := self.peek()
		self.pos += 1
		r := self.term()
		if op == "+":
			v = v + r
		else:
			v = v - r
	return v

fn eval(line: String) String:
	var cs = List[String]()
	for c in line.chars():
		cs.append(c.clone())
	var p = Parser(cs)
	v := p.expr()
	if p.peek() != "":
		p.bad = true
	if p.bad: return "error: syntax"
	if p.dz: return "error: division by zero"
	return "{v}"

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	for line in lines(stdin()):
		var blank = true
		for c in line.chars():
			if c != " " and c != "\t" and c != "\r":
				blank = false
		if blank: continue
		print(eval(line))
