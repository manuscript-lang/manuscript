import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import BytesBuilder from "@std/bytes.ms"
import bit_and, bit_or, bit_xor, shift_right, shift_right_unsigned from "@std/math/math.ms"

fn wrap(x: Int) Int:
	if x >= -2147483648 and x <= 2147483647: return x
	y := bit_and(x, 4294967295)
	if y >= 2147483648: return y - 4294967296
	return y

fn bytes_of(s: String) List[Int]:
	var out = List[Int]()
	raw := s.as_bytes()
	for b in raw.values():
		out.append(b.to_int())
	return out

fn sub(s: String, a: Int, b: Int) String:
	return s.slice(a, b).get("")

fn is_ws(c: Int) Bool:
	return c == 32 or c == 9 or c == 13

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

fn is_ident_start(c: Int) Bool:
	return (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or c == 95

fn is_ident_char(c: Int) Bool:
	return is_ident_start(c) or is_digit(c) or c == 46

fn is_ident(s: String) Bool:
	bs := bytes_of(s)
	if bs.length() == 0: return false
	if not is_ident_start(bs[0]): return false
	for i in 1..bs.length():
		if not is_ident_char(bs[i]): return false
	return true

fn reg_index(s: String) Int:
	names := ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
	return names.index_of(s).get(-1)

// end index (exclusive) of a well-formed char literal starting at i, else -1
fn lit_end(bs: List[Int], i: Int) Int:
	n := bs.length()
	if i >= n: return -1
	if bs[i] != 39: return -1
	var j = i + 1
	if j >= n: return -1
	if bs[j] == 92:
		j += 2
	else:
		j += 1
	if j < n and bs[j] == 39: return j + 1
	return -1

fn escape_value(c: Int) Int:
	if c == 110: return 10
	if c == 116: return 9
	if c == 48: return 0
	if c == 92: return 92
	if c == 39: return 39
	if c == 34: return 34
	return -1

fn strip_comment(s: String) String:
	bs := bytes_of(s)
	n := bs.length()
	var i = 0
	var in_str = false
	while i < n:
		c := bs[i]
		if in_str:
			if c == 92:
				i += 2
				continue
			if c == 34: in_str = false
			i += 1
			continue
		if c == 34:
			in_str = true
			i += 1
			continue
		if c == 39:
			e := lit_end(bs, i)
			if e >= 0:
				i = e
				continue
		if c == 59: return sub(s, 0, i)
		i += 1
	return s.clone()

fn split_ops(s: String) List[String]:
	t := s.trim()
	var out = List[String]()
	if t.length() == 0: return out
	bs := bytes_of(t)
	n := bs.length()
	var depth = 0
	var start = 0
	var i = 0
	while i < n:
		c := bs[i]
		if c == 39:
			e := lit_end(bs, i)
			if e >= 0:
				i = e
				continue
		if c == 91: depth += 1
		if c == 93 and depth > 0: depth -= 1
		if c == 44 and depth == 0:
			out.append(sub(t, start, i).trim().clone())
			start = i + 1
		i += 1
	out.append(sub(t, start, n).trim().clone())
	return out

type Term:
	sign: Int = 1
	kind: Int = 0
	val: Int = 0
	name: String = ""

fn invalid_expr(text: String) Error:
	return Error("invalid expression '{text}'")

fn parse_number(piece: String) Int!:
	bs := bytes_of(piece)
	n := bs.length()
	var base = 10
	var start = 0
	if n >= 2 and bs[0] == 48 and bs[1] == 120:
		base = 16
		start = 2
	else if n >= 2 and bs[0] == 48 and bs[1] == 98:
		base = 2
		start = 2
	if start >= n: return error(Error("bad"))
	var v = 0
	for i in start..n:
		c := bs[i]
		var d = -1
		if is_digit(c): d = c - 48
		else if c >= 97 and c <= 102: d = c - 87
		else if c >= 65 and c <= 70: d = c - 55
		if d < 0 or d >= base: return error(Error("bad"))
		v = v * base + d
		if v > 4294967295: v = 4294967296
	return ok(v)

fn parse_expr(text: String) List[Term]!:
	t := text.trim()
	bs := bytes_of(t)
	n := bs.length()
	var terms = List[Term]()
	var i = 0
	var sign = 1
	while i < n and is_ws(bs[i]): i += 1
	if i < n and (bs[i] == 43 or bs[i] == 45):
		if bs[i] == 45: sign = -1
		i += 1
	while true:
		while i < n and is_ws(bs[i]): i += 1
		if i >= n: return error(invalid_expr(t))
		if bs[i] == 39:
			e := lit_end(bs, i)
			if e < 0: return error(invalid_expr(t))
			var v = 0
			if bs[i + 1] == 92:
				v = escape_value(bs[i + 2])
				if v < 0: return error(invalid_expr(t))
			else:
				v = bs[i + 1]
				if v == 39 or v >= 128: return error(invalid_expr(t))
			terms.append(Term(sign: sign, kind: 0, val: v))
			i = e
		else:
			var j = i
			while j < n and bs[j] != 43 and bs[j] != 45: j += 1
			piece := sub(t, i, j).trim()
			if piece.length() == 0: return error(invalid_expr(t))
			pb := bytes_of(piece)
			if is_digit(pb[0]):
				r := parse_number(piece)
				if r.is_error(): return error(invalid_expr(t))
				v := r?
				if v > 4294967295: return error(Error("immediate out of range"))
				terms.append(Term(sign: sign, kind: 0, val: wrap(v)))
			else if is_ident(piece):
				terms.append(Term(sign: sign, kind: 1, name: piece.clone()))
			else:
				return error(invalid_expr(t))
			i = j
		while i < n and is_ws(bs[i]): i += 1
		if i >= n: break
		if bs[i] == 43:
			sign = 1
		else if bs[i] == 45:
			sign = -1
		else:
			return error(invalid_expr(t))
		i += 1
	return ok(terms)

type Syms:
	labels: Map[String, Int] = Map[String, Int]()
	equs: Map[String, String] = Map[String, String]()
	cache: Map[String, Int] = Map[String, Int]()
	visiting: Set[String] = Set[String]()

fn var Syms.lookup(name: String) Int!:
	if self.labels.contains(name): return ok(self.labels.get_or(name, 0))
	if self.cache.contains(name): return ok(self.cache.get_or(name, 0))
	if not self.equs.contains(name): return error(Error("undefined symbol '{name}'"))
	if self.visiting.contains(name): return error(Error("circular definition of '{name}'"))
	text := self.equs.get_or(name, "").clone()
	self.visiting.add(name.clone())
	r := self.eval(text)
	self.visiting.remove(name.clone())
	v := r?
	self.cache.add(name.clone(), v)
	return ok(v)

fn var Syms.eval(text: String) Int!:
	terms := parse_expr(text)?
	var acc = 0
	for t in terms:
		var v = t.val
		if t.kind == 1:
			v = self.lookup(t.name)?
		acc = wrap(acc + t.sign * v)
	return ok(acc)

type Operand:
	kind: Int = 0
	reg: Int = -1
	text: String = ""
	val: Int = 0

type Inst:
	op: Int = 0
	line: Int = 0
	a: Operand = Operand()
	b: Operand = Operand()

type DItem:
	addr: Int = 0
	count: Int = 1
	kind: Int = 0
	text: String = ""
	val: Int = 0
	line: Int = 0

fn bad_op(t: String) Error:
	return Error("invalid operand '{t}'")

fn parse_operand(text: String) Operand!:
	t := text.trim()
	if t.length() == 0: return error(bad_op(t))
	r := reg_index(t)
	if r >= 0: return ok(Operand(kind: 1, reg: r))
	bs := bytes_of(t)
	n := bs.length()
	if bs[0] != 91: return ok(Operand(kind: 2, text: t.clone()))
	if bs[n - 1] != 93 or n < 3: return error(bad_op(t))
	inner := sub(t, 1, n - 1)
	ib := bytes_of(inner)
	m := ib.length()
	var i = 0
	var sign = 1
	var reg = -1
	var etext = ""
	while i < m and is_ws(ib[i]): i += 1
	if i >= m: return error(bad_op(t))
	if ib[i] == 43 or ib[i] == 45:
		if ib[i] == 45: sign = -1
		i += 1
	while true:
		while i < m and is_ws(ib[i]): i += 1
		var j = i
		var lit = false
		if i < m and ib[i] == 39:
			e := lit_end(ib, i)
			if e >= 0:
				j = e
				lit = true
		if not lit:
			while j < m and ib[j] != 43 and ib[j] != 45: j += 1
		term := sub(inner, i, j).trim()
		if term.length() == 0: return error(bad_op(t))
		if not lit:
			tb := bytes_of(term)
			for c in tb:
				if c == 91 or c == 93: return error(bad_op(t))
		rr := reg_index(term)
		if rr >= 0:
			if sign < 0 or reg >= 0: return error(bad_op(t))
			reg = rr
		else:
			if sign < 0:
				etext = "{etext}-{term}"
			else:
				etext = "{etext}+{term}"
		i = j
		while i < m and is_ws(ib[i]): i += 1
		if i >= m: break
		if ib[i] == 43:
			sign = 1
		else if ib[i] == 45:
			sign = -1
		else:
			return error(bad_op(t))
		i += 1
	if etext.starts_with("+"): etext = sub(etext, 1, etext.length())
	return ok(Operand(kind: 3, reg: reg, text: etext))

fn mnemonics() List[String]:
	return ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]

fn shape_of(op: Int) Int:
	if op == 0: return 3
	if op <= 12: return 2
	if op <= 16: return 1
	if op == 17: return 4
	if op == 18: return 5
	if op == 19: return 1
	if op <= 27: return 6
	if op == 28: return 0
	if op == 29: return 1
	if op <= 31: return 5
	return 0

fn arity_of(shape: Int) Int:
	if shape == 0: return 0
	if shape == 2 or shape == 3 or shape == 4: return 2
	return 1

type Asm:
	syms: Syms = Syms()
	code: List[Inst] = List[Inst]()
	items: List[DItem] = List[DItem]()
	order: List[Int] = List[Int]()
	final: List[Inst] = List[Inst]()
	mem: List[Int] = List[Int]()
	dcount: Int = 0
	in_data: Bool = false
	budget: Int = 100000
	main_pc: Int = -1

fn var Asm.define(name: String) Void!:
	if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
	if self.syms.labels.contains(name) or self.syms.equs.contains(name):
		return error(Error("duplicate symbol '{name}'"))
	return ok(unit)

fn var Asm.too_large(n: Int) Void!:
	if self.dcount + n > 4096: return error(Error("data section too large"))
	return ok(unit)

fn var Asm.directive(word: String, args: String, line: Int) Void!:
	if word == ".text" or word == ".data":
		if args.length() > 0: return error(bad_op(args))
		self.in_data = word == ".data"
		return ok(unit)
	if word == ".equ":
		ops := split_ops(args)
		if ops.length() != 2: return error(Error("wrong number of operands for '.equ'"))
		name := ops[0]
		if not is_ident(name): return error(bad_op(name))
		self.define(name)?
		self.syms.equs.add(name.clone(), ops[1].clone())
		return ok(unit)
	if word == ".budget":
		var good = args.length() > 0
		for c in bytes_of(args):
			if not is_digit(c): good = false
		if good:
			if v := args.parse_int():
				if v >= 1 and v <= 10000000:
					self.budget = v
					return ok(unit)
		return error(bad_op(args))
	if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
		if not self.in_data: return error(Error("data directive in text section"))
		if word == ".word":
			ops := split_ops(args)
			if ops.length() == 0: return error(Error("wrong number of operands for '.word'"))
			self.too_large(ops.length())?
			for o in ops:
				self.items.append(DItem(addr: self.dcount, count: 1, kind: 1, text: o.clone(), line: line))
				self.order.append(-self.items.length())
				self.dcount += 1
			return ok(unit)
		if word == ".space":
			ops := split_ops(args)
			if ops.length() < 1 or ops.length() > 2: return error(Error("wrong number of operands for '.space'"))
			n := self.syms.eval(ops[0])?
			if n < 0: return error(bad_op(ops[0]))
			self.too_large(n)?
			var item = DItem(addr: self.dcount, count: n, kind: 0, val: 0, line: line)
			if ops.length() == 2:
				item = DItem(addr: self.dcount, count: n, kind: 1, text: ops[1].clone(), line: line)
			self.items.append(item)
			self.order.append(-self.items.length())
			self.dcount += n
			return ok(unit)
		// ascii / asciz
		bs := bytes_of(args)
		n := bs.length()
		if n < 2 or bs[0] != 34 or bs[n - 1] != 34: return error(Error("invalid string"))
		var vals = List[Int]()
		var i = 1
		while i < n - 1:
			c := bs[i]
			if c == 34: return error(Error("invalid string"))
			if c == 92:
				if i + 1 >= n - 1: return error(Error("invalid string"))
				e := escape_value(bs[i + 1])
				if e < 0: return error(Error("invalid string"))
				vals.append(e)
				i += 2
			else:
				vals.append(c)
				i += 1
		if word == ".asciz": vals.append(0)
		self.too_large(vals.length())?
		if vals.length() > 0:
			for v in vals:
				self.items.append(DItem(addr: self.dcount, count: 1, kind: 0, val: v, line: line))
				self.dcount += 1
			// order entries for each item
			for _k in 0..vals.length():
				self.order.append(-(self.items.length() - vals.length() + _k + 1))
		return ok(unit)
	return error(Error("unknown directive '{word}'"))

fn var Asm.instruction(word: String, args: String, line: Int) Void!:
	if self.in_data: return error(Error("instruction in data section"))
	names := mnemonics()
	var op = -1
	if word == "jz":
		op = 21
	else if word == "jnz":
		op = 22
	else:
		op = names.index_of(word).get(-1)
	if op < 0: return error(Error("unknown mnemonic '{word}'"))
	pieces := split_ops(args)
	var ops = List[Operand]()
	for p in pieces:
		ops.append(parse_operand(p)?)
	shape := shape_of(op)
	if ops.length() != arity_of(shape): return error(Error("wrong number of operands for '{word}'"))
	var okc = true
	if shape == 1 or shape == 2:
		okc = ops[0].kind == 1
	else if shape == 3:
		if ops[0].kind == 1:
			okc = true
		else if ops[0].kind == 3:
			okc = ops[1].kind != 3
		else:
			okc = false
	else if shape == 4:
		okc = ops[0].kind == 1 and ops[1].kind == 3
	else if shape == 6:
		okc = ops[0].kind == 2
	if not okc: return error(Error("invalid operands for '{word}'"))
	var ins = Inst(op: op, line: line)
	if ops.length() >= 1: ins.a = ops[0].clone()
	if ops.length() >= 2: ins.b = ops[1].clone()
	self.code.append(ins)
	self.order.append(self.code.length() - 1)
	return ok(unit)

fn var Asm.line(raw: String, lineno: Int) Void!:
	s := strip_comment(raw).trim()
	if s.length() == 0: return ok(unit)
	bs := bytes_of(s)
	n := bs.length()
	var pos = 0
	while true:
		while pos < n and is_ws(bs[pos]): pos += 1
		if pos >= n: return ok(unit)
		if not is_ident_start(bs[pos]): break
		var j = pos
		while j < n and is_ident_char(bs[j]): j += 1
		if j < n and bs[j] == 58:
			name := sub(s, pos, j)
			self.define(name)?
			if self.in_data:
				self.syms.labels.add(name.clone(), self.dcount)
			else:
				self.syms.labels.add(name.clone(), self.code.length())
				if name == "main": self.main_pc = self.code.length()
			pos = j + 1
		else:
			break
	rest := sub(s, pos, n)
	rb := bytes_of(rest)
	var k = 0
	while k < rb.length() and not is_ws(rb[k]): k += 1
	word := sub(rest, 0, k)
	args := sub(rest, k, rb.length()).trim()
	if word.starts_with("."):
		return self.directive(word, args, lineno)
	return self.instruction(word, args, lineno)

fn var Asm.resolve_operand(op: Operand) Operand!:
	if op.kind == 2:
		v := self.syms.eval(op.text)?
		return ok(Operand(kind: 2, val: v))
	if op.kind == 3:
		var v = 0
		if op.text.length() > 0:
			v = self.syms.eval(op.text)?
		return ok(Operand(kind: 3, reg: op.reg, val: v))
	return ok(op.clone())

// resolves one entry of `order`; returns the source line through the error path via `cur_line`
fn var Asm.resolve(k: Int) Void!:
	if k >= 0:
		ins := self.code[k].clone()
		a := self.resolve_operand(ins.a)?
		b := self.resolve_operand(ins.b)?
		if shape_of(ins.op) == 6:
			if a.val < 0 or a.val >= self.code.length(): return error(Error("invalid jump target"))
		self.final.append(Inst(op: ins.op, line: ins.line, a: a, b: b))
		return ok(unit)
	item := self.items[-k - 1]
	var v = item.val
	if item.kind == 1:
		v = self.syms.eval(item.text)?
	for i in 0..item.count:
		self.mem[item.addr + i] = v
	return ok(unit)

fn item_line(asm: Asm, k: Int) Int:
	if k >= 0: return asm.code[k].line
	return asm.items[-k - 1].line

type VM:
	regs: List[Int] = List[Int]()
	mem: List[Int] = List[Int]()
	pc: Int = 0
	steps: Int = 0
	z: Bool = false
	l: Bool = false
	halted: Bool = false
	out: BytesBuilder = BytesBuilder()
	last: Int = -1
	input: List[Int] = List[Int]()
	inpos: Int = 0

fn VM.addr(op: Operand) Int:
	if op.reg >= 0: return wrap(self.regs[op.reg] + op.val)
	return wrap(op.val)

fn VM.read(op: Operand) Int!:
	if op.kind == 1: return ok(self.regs[op.reg])
	if op.kind == 2: return ok(op.val)
	a := self.addr(op)
	if a < 0 or a >= 4096: return error(Error("memory access out of range: {a}"))
	return ok(self.mem[a])

fn var VM.write(op: Operand, v: Int) Void!:
	if op.kind == 1:
		self.regs[op.reg] = v
		return ok(unit)
	a := self.addr(op)
	if a < 0 or a >= 4096: return error(Error("memory access out of range: {a}"))
	self.mem[a] = v
	return ok(unit)

fn var VM.push_val(v: Int) Void!:
	if self.regs[8] <= 0: return error(Error("stack overflow"))
	self.regs[8] = self.regs[8] - 1
	a := self.regs[8]
	if a < 0 or a >= 4096: return error(Error("memory access out of range: {a}"))
	self.mem[a] = v
	return ok(unit)

fn var VM.pop_val() Int!:
	if self.regs[8] >= 4096: return error(Error("stack underflow"))
	a := self.regs[8]
	if a < 0 or a >= 4096: return error(Error("memory access out of range: {a}"))
	v := self.mem[a]
	self.regs[8] = a + 1
	return ok(v)

fn var VM.emit(s: String) Void:
	if s.length() == 0: return
	b := s.as_bytes()
	self.out.append_bytes(b)

fn var VM.step(code: List[Inst]) Void!:
	ins := code[self.pc]
	op := ins.op
	var next = self.pc + 1
	if op == 0:
		v := self.read(ins.b)?
		self.write(ins.a, v)?
	else if op <= 12:
		s := self.read(ins.b)?
		d := self.regs[ins.a.reg]
		if op == 1:
			self.regs[ins.a.reg] = wrap(d + s)
		else if op == 2:
			self.regs[ins.a.reg] = wrap(d - s)
		else if op == 3:
			self.regs[ins.a.reg] = wrap(d * s)
		else if op == 4:
			if s == 0: return error(Error("division by zero"))
			self.regs[ins.a.reg] = wrap(d / s)
		else if op == 5:
			if s == 0: return error(Error("division by zero"))
			self.regs[ins.a.reg] = wrap(d - (d / s) * s)
		else if op == 6:
			self.regs[ins.a.reg] = bit_and(d, s)
		else if op == 7:
			self.regs[ins.a.reg] = bit_or(d, s)
		else if op == 8:
			self.regs[ins.a.reg] = bit_xor(d, s)
		else if op == 9:
			c := bit_and(s, 31)
			self.regs[ins.a.reg] = wrap(d * pow2(c))
		else if op == 10:
			c := bit_and(s, 31)
			self.regs[ins.a.reg] = wrap(shift_right_unsigned(bit_and(d, 4294967295), c))
		else if op == 11:
			c := bit_and(s, 31)
			self.regs[ins.a.reg] = shift_right(d, c)
		else:
			self.z = d == s
			self.l = d < s
	else if op == 13:
		self.regs[ins.a.reg] = wrap(-self.regs[ins.a.reg])
	else if op == 14:
		self.regs[ins.a.reg] = -self.regs[ins.a.reg] - 1
	else if op == 15:
		self.regs[ins.a.reg] = wrap(self.regs[ins.a.reg] + 1)
	else if op == 16:
		self.regs[ins.a.reg] = wrap(self.regs[ins.a.reg] - 1)
	else if op == 17:
		self.regs[ins.a.reg] = self.addr(ins.b)
	else if op == 18:
		v := self.read(ins.a)?
		self.push_val(v)?
	else if op == 19:
		v := self.pop_val()?
		self.regs[ins.a.reg] = v
	else if op <= 26:
		var take = false
		if op == 20: take = true
		else if op == 21: take = self.z
		else if op == 22: take = not self.z
		else if op == 23: take = self.l
		else if op == 24: take = self.l or self.z
		else if op == 25: take = not self.l and not self.z
		else: take = not self.l
		if take: next = ins.a.val
	else if op == 27:
		self.push_val(self.pc + 1)?
		next = ins.a.val
	else if op == 28:
		next = self.pop_val()?
	else if op == 29:
		if self.inpos >= self.input.length(): return error(Error("input exhausted"))
		self.regs[ins.a.reg] = self.input[self.inpos]
		self.inpos += 1
	else if op == 30:
		v := self.read(ins.a)?
		self.emit("{v}\n")
		self.last = 10
	else if op == 31:
		v := self.read(ins.a)?
		if v < 0 or v > 127: return error(Error("invalid character"))
		if b := v.to_uint8():
			self.out.append(b)
		self.last = v
	else if op == 32:
		self.halted = true
	self.pc = next
	self.steps += 1
	return ok(unit)

fn parse_input(text: String) List[Int]:
	var out = List[Int]()
	for tok in text.fields():
		bs := bytes_of(tok)
		var i = 0
		var neg = false
		if bs.length() > 0 and bs[0] == 45:
			neg = true
			i = 1
		if i >= bs.length(): continue
		var good = true
		var v = 0
		for j in i..bs.length():
			if not is_digit(bs[j]):
				good = false
			else:
				v = bit_and(v * 10 + bs[j] - 48, 4294967295)
		if not good: continue
		if neg: v = -v
		out.append(wrap(v))
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Void!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	all := text.split("\n", none)
	var src = List[String]()
	var rest = ""
	var seen = false
	for ln in all:
		var l = ln.clone()
		if l.ends_with("\r"): l = sub(l, 0, l.length() - 1)
		if seen:
			rest = "{rest} {l}"
		else if l == "====":
			seen = true
		else:
			src.append(l.clone())
	var asm = Asm()
	for _i in 0..4096:
		asm.mem.append(0)
	for i in 0..src.length():
		r := asm.line(src[i], i + 1)
		if r.is_error():
			print("asm error line {i + 1}: {r.err().message}")
			return
	for k in asm.order.clone():
		r := asm.resolve(k)
		if r.is_error():
			print("asm error line {item_line(asm, k)}: {r.err().message}")
			return
	var vm = VM()
	for _i in 0..10:
		vm.regs.append(0)
	vm.regs[8] = 4096
	vm.mem = asm.mem.clone()
	vm.input = parse_input(rest)
	if asm.main_pc >= 0: vm.pc = asm.main_pc
	code := asm.final
	n := code.length()
	var trap = ""
	var trapline = "-"
	while true:
		if vm.halted: break
		if vm.steps == asm.budget:
			trap = "budget exceeded"
			trapline = "{code[vm.pc].line}"
			if vm.pc < 0 or vm.pc >= n: trapline = "-"
			break
		if vm.pc < 0 or vm.pc >= n:
			trap = "pc out of range"
			break
		r := vm.step(code)
		if r.is_error():
			trap = r.err().message
			trapline = "{code[vm.pc].line}"
			break
	outtext := vm.out.build().decode_utf8().get("")
	print(outtext, end: "")
	if outtext.length() > 0 and not outtext.ends_with("\n"): print("")
	if trap == "":
		print("-- halted after {vm.steps} steps")
	else:
		print("-- trap: {trap} (pc={vm.pc} line={trapline}) after {vm.steps} steps")
	r := vm.regs
	print("regs: r0={r[0]} r1={r[1]} r2={r[2]} r3={r[3]} r4={r[4]} r5={r[5]} r6={r[6]} r7={r[7]} sp={r[8]} bp={r[9]}")
	print("flags: Z={if vm.z: 1 else: 0} L={if vm.l: 1 else: 0}")

fn pow2(c: Int) Int:
	var r = 1
	for _i in 0..c:
		r = r * 2
	return r
