import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type P:
	toks: List[String]
	pos: Int = 0
	bad: Bool = false
	dz: Bool = false

fn P.peek() String:
	return self.toks.get(self.pos, "")

fn is_num(t: String) Bool:
	if t.length() == 0: return false
	return "0123456789".contains(t.slice(0, 1).get(""))

fn var P.atom() Int:
	t := self.peek()
	if t == "-":
		self.pos += 1
		return 0 - self.atom()
	if t == "(":
		self.pos += 1
		v := self.expr()
		if self.peek() == ")":
			self.pos += 1
		else:
			self.bad = true
		return v
	if is_num(t):
		self.pos += 1
		if n := t.parse_int():
			return n
		self.bad = true
		return 0
	self.bad = true
	return 0

fn var P.term() Int:
	var v = self.atom()
	while self.peek() == "*" or self.peek() == "/":
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
	var toks = List[String]()
	var cur = ""
	for c in line.chars():
		if "0123456789".contains(c):
			cur = cur + c
			continue
		if cur.length() > 0:
			toks.append(cur.clone())
			cur = ""
		if c == " " or c == "\t" or c == "\r": continue
		if "+-*/()".contains(c):
			toks.append(c.clone())
		else:
			return none
	if cur.length() > 0:
		toks.append(cur.clone())
	return toks

fn eval(line: String) String:
	tk := tokenize(line)
	if tk.is_none(): return "error: syntax"
	var p = P(tk.get([]))
	v := p.expr()
	if p.pos < p.toks.length(): p.bad = true
	if p.bad: return "error: syntax"
	if p.dz: return "error: division by zero"
	return "{v}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(eval(line))
