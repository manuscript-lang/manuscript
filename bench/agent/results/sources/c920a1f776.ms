import stdin, stdout_bytes from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import BytesBuilder from "@std/bytes.ms"
import bit_and, bit_xor, bit_or, bit_not, shift_left, shift_right, shift_right_unsigned from "@std/math/math.ms"

fn w32(x: Int) Int:
	y := bit_and(x, 4294967295)
	if y >= 2147483648: return y - 4294967296
	return y

fn sub(s: String, a: Int, b: Int) String:
	r := s.slice(a, b)
	if v := r: return v
	return ""

fn bytes_of(s: String) List[Int]:
	var out = List[Int]()
	for b in s.to_bytes().values():
		out.append(b.to_int())
	return out

fn is_digit(c: Int) Bool: c >= 48 and c <= 57

fn is_ident_start(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_ident_char(c: Int) Bool:
	return is_ident_start(c) or is_digit(c) or c == 46

fn is_ident(s: String) Bool:
	b := bytes_of(s)
	if b.length() == 0: return false
	if not is_ident_start(b[0]): return false
	for i in 1..b.length():
		if not is_ident_char(b[i]): return false
	return true

fn digit_val(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return 99

fn reg_index(s: String) Int:
	names := ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
	for i in 0..10:
		if names[i] == s: return i
	return -1

fn escape_val(c: Int) Int:
	if c == 110: return 10
	if c == 116: return 9
	if c == 48: return 0
	if c == 92: return 92
	if c == 39: return 39
	if c == 34: return 34
	return -1

type Term:
	sign: Int
	text: String

fn split_terms(s: String) List[Term]:
	b := bytes_of(s)
	n := b.length()
	var terms = List[Term]()
	var i = 0
	var sign = 1
	while i < n and (b[i] == 32 or b[i] == 9):
		i += 1
	if i < n and (b[i] == 43 or b[i] == 45):
		if b[i] == 45: sign = -1
		i += 1
	while true:
		start := i
		var q = false
		while i < n:
			c := b[i]
			if q:
				if c == 92: i += 1
				else if c == 39: q = false
			else:
				if c == 39: q = true
				else if c == 43 or c == 45: break
			i += 1
		e := if i > n: n else: i
		terms.append(Term(sign, sub(s, start, e).trim()))
		if i >= n: break
		sign = if b[i] == 45: -1 else: 1
		i += 1
	return terms

fn split_ops(s: String) List[String]:
	var out = List[String]()
	if s == "": return out
	b := bytes_of(s)
	n := b.length()
	var depth = 0
	var q = false
	var start = 0
	var i = 0
	while i < n:
		c := b[i]
		if q:
			if c == 92: i += 1
			else if c == 39: q = false
		else:
			if c == 39: q = true
			else if c == 91: depth += 1
			else if c == 93:
				if depth > 0: depth -= 1
			else if c == 44 and depth == 0:
				out.append(sub(s, start, i).trim())
				start = i + 1
		i += 1
	out.append(sub(s, start, n).trim())
	return out

fn strip_comment(s: String) String:
	b := bytes_of(s)
	n := b.length()
	var q = 0
	var i = 0
	while i < n:
		c := b[i]
		if q != 0:
			if c == 92: i += 1
			else if c == q: q = 0
		else:
			if c == 34 or c == 39: q = c
			else if c == 59: return sub(s, 0, i).clone()
		i += 1
	return s.clone()

fn parse_string(s: String) List[Int]?:
	b := bytes_of(s)
	n := b.length()
	if n < 2 or b[0] != 34 or b[n - 1] != 34: return none
	var out = List[Int]()
	var i = 1
	while i < n - 1:
		c := b[i]
		if c == 34: return none
		if c == 92:
			if i + 1 >= n - 1: return none
			v := escape_val(b[i + 1])
			if v < 0: return none
			out.append(v)
			i += 2
		else:
			out.append(c)
			i += 1
	return out

type Operand:
	kind: Int
	reg: Int = -1
	text: String = ""
	terms: List[Term] = []

type Item:
	line: Int
	instr: Bool
	op: Int = 0
	ops: List[Operand] = []
	mode: Int = 0
	text: String = ""
	val: Int = 0
	count: Int = 0

type Syms:
	labels: Map[String, Int] = Map[String, Int]()
	equs: Map[String, String] = Map[String, String]()
	cache: Map[String, Int] = Map[String, Int]()
	visiting: Set[String] = Set[String]()
	textlabels: Set[String] = Set[String]()
	cur_line: Int = 0

fn var Syms.eval_sym(name: String) Int!:
	if self.labels.contains(name): return ok(self.labels.get_or(name, 0))
	if self.cache.contains(name): return ok(self.cache.get_or(name, 0))
	if self.equs.contains(name):
		if self.visiting.contains(name):
			return error(Error("circular definition of '{name}'"))
		self.visiting.add(name.clone())
		body := self.equs.get_or(name, "")
		v := self.eval_expr(body)?
		self.visiting.remove(name.clone())
		self.cache[name.clone()] = v
		return ok(v)
	return error(Error("undefined symbol '{name}'"))

fn var Syms.eval_term(t: String, whole: String) Int!:
	bad := Error("invalid expression '{whole}'")
	if t == "": return error(bad)
	b := bytes_of(t)
	n := b.length()
	c := b[0]
	if is_digit(c):
		var base = 10
		var i = 0
		if n >= 2 and c == 48 and b[1] == 120:
			base = 16
			i = 2
		else if n >= 2 and c == 48 and b[1] == 98:
			base = 2
			i = 2
		if i >= n: return error(bad)
		var acc = 0
		var over = false
		while i < n:
			d := digit_val(b[i])
			if d >= base: return error(bad)
			acc = acc * base + d
			if acc > 4294967295:
				over = true
				acc = 4294967296
			i += 1
		if over: return error(Error("immediate out of range"))
		return ok(w32(acc))
	if c == 39:
		if n < 3 or b[n - 1] != 39: return error(bad)
		if n == 3:
			if b[1] == 92 or b[1] == 39: return error(bad)
			return ok(b[1])
		if n == 4 and b[1] == 92:
			v := escape_val(b[2])
			if v < 0: return error(bad)
			return ok(v)
		return error(bad)
	if is_ident(t):
		return self.eval_sym(t)
	return error(bad)

fn var Syms.eval_expr(text: String) Int!:
	whole := text.trim()
	var acc = 0
	for term in split_terms(whole):
		v := self.eval_term(term.text, whole)?
		acc = w32(acc + term.sign * v)
	return ok(acc)

fn mnemonic_op(w: String) Int:
	names := ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]
	for i in 0..names.length():
		if names[i] == w: return i
	if w == "jz": return 21
	if w == "jnz": return 22
	return -1

fn arity(op: Int) Int:
	if op <= 12 or op == 17: return 2
	if op == 28 or op >= 32: return 0
	return 1

fn classes_ok(op: Int, ops: List[Operand]) Bool:
	if op == 0:
		if ops[0].kind == 0: return true
		if ops[0].kind == 2: return ops[1].kind != 2
		return false
	if op <= 12: return ops[0].kind == 0
	if op <= 16: return ops[0].kind == 0
	if op == 17: return ops[0].kind == 0 and ops[1].kind == 2
	if op == 18: return true
	if op == 19: return ops[0].kind == 0
	if op <= 27: return ops[0].kind == 1
	if op == 29: return ops[0].kind == 0
	return true

fn parse_operand(t: String) Operand!:
	bad := Error("invalid operand '{t}'")
	if t == "": return error(bad)
	r := reg_index(t)
	if r >= 0: return ok(Operand(kind: 0, reg: r))
	if t.starts_with("["):
		n := t.length()
		if n < 2 or not t.ends_with("]"): return error(bad)
		inner := sub(t, 1, n - 1).trim()
		if inner == "": return error(bad)
		var reg = -1
		var terms = List[Term]()
		for term in split_terms(inner):
			if term.text == "": return error(bad)
			ri := reg_index(term.text)
			if ri >= 0:
				if term.sign < 0 or reg >= 0: return error(bad)
				reg = ri
			else:
				terms.append(term)
		return ok(Operand(kind: 2, reg: reg, terms: terms))
	return ok(Operand(kind: 1, text: t))

type Asm:
	syms: Syms = Syms()
	dlen: Int = 0
	ninstr: Int = 0
	in_data: Bool = false
	budget: Int = 100000

fn var Asm.define(name: String) Unit!:
	if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
	if self.syms.labels.contains(name) or self.syms.equs.contains(name):
		return error(Error("duplicate symbol '{name}'"))
	return ok(unit)

fn label_prefix(s: String) String:
	b := bytes_of(s)
	if b.length() == 0 or not is_ident_start(b[0]): return ""
	var i = 1
	while i < b.length() and is_ident_char(b[i]):
		i += 1
	if i < b.length() and b[i] == 58: return sub(s, 0, i)
	return ""

fn var Asm.add_data(n: Int) Unit!:
	self.dlen += n
	if self.dlen > 4096: return error(Error("data section too large"))
	return ok(unit)

fn var Asm.line(raw: String, no: Int, var items: List[Item]) Unit!:
	self.syms.cur_line = no
	var rest = strip_comment(raw).trim()
	while true:
		name := label_prefix(rest)
		if name == "": break
		self.define(name)?
		if self.in_data:
			self.syms.labels[name.clone()] = self.dlen
		else:
			self.syms.labels[name.clone()] = self.ninstr
			self.syms.textlabels.add(name.clone())
		rest = sub(rest, name.length() + 1, rest.length()).trim()
	if rest == "": return ok(unit)
	var wend = 0
	rb := bytes_of(rest)
	while wend < rb.length() and rb[wend] != 32 and rb[wend] != 9:
		wend += 1
	word := sub(rest, 0, wend)
	args := sub(rest, wend, rest.length()).trim()
	if word.starts_with("."):
		if word == ".text" or word == ".data":
			if args != "": return error(Error("invalid operand '{args}'"))
			self.in_data = word == ".data"
			return ok(unit)
		if word == ".equ":
			ops := split_ops(args)
			if ops.length() != 2: return error(Error("wrong number of operands for '.equ'"))
			if not is_ident(ops[0]): return error(Error("invalid operand '{ops[0]}'"))
			self.define(ops[0])?
			self.syms.equs[ops[0].clone()] = ops[1].clone()
			return ok(unit)
		if word == ".budget":
			ab := bytes_of(args)
			var v = 0
			var good = ab.length() > 0 and ab.length() <= 12
			for c in ab:
				if not is_digit(c): good = false
				else: v = v * 10 + (c - 48)
			if not good or v < 1 or v > 10000000: return error(Error("invalid operand '{args}'"))
			self.budget = v
			return ok(unit)
		if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
			if not self.in_data: return error(Error("data directive in text section"))
			if word == ".word":
				ops := split_ops(args)
				if ops.length() == 0: return error(Error("wrong number of operands for '.word'"))
				self.add_data(ops.length())?
				for o in ops:
					items.append(Item(line: no, instr: false, mode: 0, text: o))
				return ok(unit)
			if word == ".space":
				ops := split_ops(args)
				if ops.length() < 1 or ops.length() > 2: return error(Error("wrong number of operands for '.space'"))
				n := self.syms.eval_expr(ops[0])?
				if n < 0: return error(Error("invalid operand '{ops[0]}'"))
				self.add_data(n)?
				fill := if ops.length() == 2: ops[1].clone() else: "0".clone()
				items.append(Item(line: no, instr: false, mode: 2, text: fill, count: n))
				return ok(unit)
			parsed := parse_string(args)
			if bytes := parsed:
				self.add_data(bytes.length() + (if word == ".asciz": 1 else: 0))?
				for c in bytes:
					items.append(Item(line: no, instr: false, mode: 1, val: c))
				if word == ".asciz":
					items.append(Item(line: no, instr: false, mode: 1, val: 0))
				return ok(unit)
			return error(Error("invalid string"))
		return error(Error("unknown directive '{word}'"))
	if self.in_data: return error(Error("instruction in data section"))
	op := mnemonic_op(word)
	if op < 0: return error(Error("unknown mnemonic '{word}'"))
	var ops = List[Operand]()
	for t in split_ops(args):
		ops.append(parse_operand(t)?)
	if ops.length() != arity(op): return error(Error("wrong number of operands for '{word}'"))
	if not classes_ok(op, ops): return error(Error("invalid operands for '{word}'"))
	items.append(Item(line: no, instr: true, op: op, ops: ops))
	self.ninstr += 1
	return ok(unit)

type Instr:
	op: Int
	line: Int
	ak: Int = 0
	ar: Int = -1
	av: Int = 0
	bk: Int = 0
	br: Int = -1
	bv: Int = 0

fn var Syms.resolve(o: Operand, op: Int, n: Int) Operand!:
	if o.kind == 0: return ok(Operand(kind: 0, reg: o.reg))
	if o.kind == 1:
		v := self.eval_expr(o.text)?
		if op >= 20 and op <= 27:
			if v < 0 or v >= n: return error(Error("invalid jump target"))
		return ok(Operand(kind: 1, text: "", reg: -1, terms: [Term(1, "{v}")]))
	var sum = 0
	for t in o.terms:
		v := self.eval_expr(t.text)?
		sum = w32(sum + t.sign * v)
	return ok(Operand(kind: 2, reg: o.reg, terms: [Term(1, "{sum}")]))

fn opval(o: Operand) Int:
	if o.kind == 0: return 0
	for t in o.terms:
		return t.text.parse_int().get(0)
	return 0

fn var Syms.pass2(items: List[Item], n: Int, var code: List[Instr], var data: List[Int]) Unit!:
	for it in items:
		self.cur_line = it.line
		if it.instr:
			var ins = Instr(op: it.op, line: it.line)
			if it.ops.length() >= 1:
				a := self.resolve(it.ops[0], it.op, n)?
				ins.ak = a.kind
				ins.ar = a.reg
				ins.av = opval(a)
			if it.ops.length() >= 2:
				b := self.resolve(it.ops[1], it.op, n)?
				ins.bk = b.kind
				ins.br = b.reg
				ins.bv = opval(b)
			code.append(ins)
		else if it.mode == 0:
			data.append(self.eval_expr(it.text)?)
		else if it.mode == 1:
			data.append(it.val)
		else:
			f := self.eval_expr(it.text)?
			for _i in 0..it.count:
				data.append(f)
	return ok(unit)

type Machine:
	regs: List[Int]
	mem: List[Int]
	input: List[Int]
	out: BytesBuilder
	inpos: Int = 0
	z: Int = 0
	l: Int = 0
	trap: String = ""
	steps: Int = 0
	pc: Int = 0
	last: Int = 10
	any_out: Bool = false

fn var Machine.rd(k: Int, r: Int, v: Int) Int:
	if k == 0: return self.regs.get(r, 0)
	if k == 1: return v
	base := if r >= 0: self.regs.get(r, 0) else: 0
	addr := w32(base + v)
	if addr < 0 or addr >= 4096:
		self.trap = "memory access out of range: {addr}"
		return 0
	return self.mem.get(addr, 0)

fn var Machine.wr_addr(addr: Int, val: Int) Unit:
	if addr < 0 or addr >= 4096:
		self.trap = "memory access out of range: {addr}"
		return
	self.mem.set(addr, val)

fn var Machine.push(v: Int) Unit:
	sp := self.regs.get(8, 0)
	if sp <= 0:
		self.trap = "stack overflow"
		return
	self.regs.set(8, sp - 1)
	self.wr_addr(sp - 1, v)

fn var Machine.pop() Int:
	sp := self.regs.get(8, 0)
	if sp >= 4096:
		self.trap = "stack underflow"
		return 0
	if sp < 0:
		self.trap = "memory access out of range: {sp}"
		return 0
	v := self.mem.get(sp, 0)
	self.regs.set(8, sp + 1)
	return v

fn alu(op: Int, d: Int, s: Int) Int:
	if op == 1: return w32(d + s)
	if op == 2: return w32(d - s)
	if op == 3: return w32(d * s)
	if op == 4: return w32(d / s)
	if op == 5: return w32(d % s)
	if op == 6: return w32(bit_and(d, s))
	if op == 7: return w32(bit_or(d, s))
	if op == 8: return w32(bit_xor(d, s))
	c := bit_and(s, 31)
	if op == 9: return w32(shift_left(d, c))
	if op == 10: return w32(shift_right_unsigned(bit_and(d, 4294967295), c))
	return w32(shift_right(d, c))

fn var Machine.putc(c: Int) Unit:
	self.out.append(c.to_uint8().get(0))
	self.last = c
	self.any_out = true

fn var Machine.run(code: List[Instr], start: Int, budget: Int) Unit:
	n := code.length()
	self.pc = start
	while true:
		if self.steps == budget:
			self.trap = "budget exceeded"
			break
		pc := self.pc
		if pc < 0 or pc >= n:
			self.trap = "pc out of range"
			break
		ins := code[pc]
		op := ins.op
		var next = pc + 1
		if op == 0:
			s := self.rd(ins.bk, ins.br, ins.bv)
			if self.trap != "": break
			if ins.ak == 0:
				self.regs.set(ins.ar, s)
			else:
				base := if ins.ar >= 0: self.regs.get(ins.ar, 0) else: 0
				self.wr_addr(w32(base + ins.av), s)
				if self.trap != "": break
		else if op <= 12:
			s := self.rd(ins.bk, ins.br, ins.bv)
			if self.trap != "": break
			d := self.regs.get(ins.ar, 0)
			if op == 12:
				self.z = if d == s: 1 else: 0
				self.l = if d < s: 1 else: 0
			else:
				if (op == 4 or op == 5) and s == 0:
					self.trap = "division by zero"
					break
				self.regs.set(ins.ar, alu(op, d, s))
		else if op <= 16:
			d := self.regs.get(ins.ar, 0)
			r := if op == 13: w32(0 - d) else if op == 14: w32(bit_not(d)) else if op == 15: w32(d + 1) else: w32(d - 1)
			self.regs.set(ins.ar, r)
		else if op == 17:
			base := if ins.br >= 0: self.regs.get(ins.br, 0) else: 0
			self.regs.set(ins.ar, w32(base + ins.bv))
		else if op == 18:
			v := self.rd(ins.ak, ins.ar, ins.av)
			if self.trap != "": break
			self.push(v)
			if self.trap != "": break
		else if op == 19:
			v := self.pop()
			if self.trap != "": break
			self.regs.set(ins.ar, v)
		else if op <= 26:
			z := self.z == 1
			l := self.l == 1
			var take = true
			if op == 21: take = z
			else if op == 22: take = not z
			else if op == 23: take = l
			else if op == 24: take = l or z
			else if op == 25: take = not l and not z
			else if op == 26: take = not l
			if take: next = ins.av
		else if op == 27:
			self.push(pc + 1)
			if self.trap != "": break
			next = ins.av
		else if op == 28:
			v := self.pop()
			if self.trap != "": break
			next = v
		else if op == 29:
			if self.inpos >= self.input.length():
				self.trap = "input exhausted"
				break
			self.regs.set(ins.ar, self.input.get(self.inpos, 0))
			self.inpos += 1
		else if op == 30:
			v := self.rd(ins.ak, ins.ar, ins.av)
			if self.trap != "": break
			self.out.append_bytes("{v}\n".to_bytes())
			self.last = 10
			self.any_out = true
		else if op == 31:
			v := self.rd(ins.ak, ins.ar, ins.av)
			if self.trap != "": break
			if v < 0 or v > 127:
				self.trap = "invalid character"
				break
			self.putc(v)
		else if op == 32:
			self.steps += 1
			break
		self.steps += 1
		self.pc = next

fn parse_input(lines: List[String]) List[Int]:
	var out = List[Int]()
	for ln in lines:
		for tok in ln.fields():
			b := bytes_of(tok)
			var i = 0
			var neg = false
			if b.length() > 0 and b[0] == 45:
				neg = true
				i = 1
			if i >= b.length(): continue
			var good = true
			var acc = 0
			while i < b.length():
				if not is_digit(b[i]):
					good = false
					break
				acc = bit_and(acc * 10 + (b[i] - 48), 4294967295)
				i += 1
			if good: out.append(w32(if neg: 0 - acc else: acc))
	return out

fn emit(text: String) Unit!:
	var o = stdout_bytes()
	o.write(text.to_bytes())?

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	raw := read_all(stdin(), none)?
	text := raw.decode_utf8().get("")
	all := text.lines()
	var src = List[String]()
	var inp = List[String]()
	var seen = false
	for ln in all:
		if seen: inp.append(ln.clone())
		else if ln == "====": seen = true
		else: src.append(ln.clone())
	var asm = Asm()
	var items = List[Item]()
	for i in 0..src.length():
		r := asm.line(src[i], i + 1, var items)
		if r.is_error():
			emit("asm error line {i + 1}: {r.err().message}\n")?
			return ok(unit)
	var code = List[Instr]()
	var data = List[Int]()
	r2 := asm.syms.pass2(items, asm.ninstr, var code, var data)
	if r2.is_error():
		emit("asm error line {asm.syms.cur_line}: {r2.err().message}\n")?
		return ok(unit)
	var mem = List[Int]()
	for i in 0..4096:
		mem.append(if i < data.length(): data[i] else: 0)
	var regs = List[Int]()
	for _i in 0..10: regs.append(0)
	regs.set(8, 4096)
	var m = Machine(regs, mem, parse_input(inp), BytesBuilder())
	start := if asm.syms.textlabels.contains("main"): asm.syms.labels.get_or("main", 0) else: 0
	m.run(code, start, asm.budget)
	if m.any_out and m.last != 10: m.putc(10)
	var summary = ""
	if m.trap == "":
		summary = "-- halted after {m.steps} steps\n"
	else:
		line := if m.trap == "pc out of range": "-" else: "{code[m.pc].line}"
		summary = "-- trap: {m.trap} (pc={m.pc} line={line}) after {m.steps} steps\n"
	summary += "regs: r0={m.regs[0]} r1={m.regs[1]} r2={m.regs[2]} r3={m.regs[3]} r4={m.regs[4]} r5={m.regs[5]} r6={m.regs[6]} r7={m.regs[7]} sp={m.regs[8]} bp={m.regs[9]}\n"
	summary += "flags: Z={m.z} L={m.l}\n"
	m.out.append_bytes(summary.to_bytes())
	emit_b := stdout_bytes()
	var o2 = emit_b
	o2.write(m.out.build())?
