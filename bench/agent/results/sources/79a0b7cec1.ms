import Bytes from "@std/bytes.ms"
import bit_and, bit_or, bit_xor, shift_left, shift_right, shift_right_unsigned from "@std/math/math.ms"
import read_all from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"
import from_scalars from "@std/string.ms"

fn wrap(x: Int) Int:
	m := ((x % 4294967296) + 4294967296) % 4294967296
	if m >= 2147483648: return m - 4294967296
	return m

fn at(b: Bytes, i: Int) Int:
	if i < 0 or i >= b.length(): return -1
	return b.get(i).to_int()

fn str(b: Bytes) String:
	return b.decode_utf8().get("?")

fn is_ws(c: Int) Bool:
	return c == 32 or (c >= 9 and c <= 13)

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

fn is_ident_start(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_ident_char(c: Int) Bool:
	return is_ident_start(c) or is_digit(c) or c == 46

fn is_ident(b: Bytes) Bool:
	n := b.length()
	if n == 0 or not is_ident_start(at(b, 0)): return false
	for i in 1..n:
		if not is_ident_char(at(b, i)): return false
	return true

fn digit_val(c: Int) Int:
	if is_digit(c): return c - 48
	if c >= 97 and c <= 102: return c - 97 + 10
	if c >= 65 and c <= 70: return c - 65 + 10
	return -1

fn trim(b: Bytes) Bytes:
	var s = 0
	var e = b.length()
	while s < e and is_ws(at(b, s)):
		s += 1
	while e > s and is_ws(at(b, e - 1)):
		e -= 1
	return b.view(s, e).clone()

fn skip_char(b: Bytes, i: Int) Int:
	var j = i + 1
	if at(b, j) == 92:
		j += 2
	else:
		j += 1
	if at(b, j) == 39: return j + 1
	return i + 1

fn strip_comment(b: Bytes) Bytes:
	n := b.length()
	var i = 0
	while i < n:
		c := at(b, i)
		if c == 59: return b.view(0, i).clone()
		if c == 34:
			var j = i + 1
			var closed = false
			while j < n:
				d := at(b, j)
				if d == 92:
					j += 2
					continue
				if d == 34:
					closed = true
					break
				j += 1
			if not closed: return b.clone()
			i = j + 1
			continue
		if c == 39:
			i = skip_char(b, i)
			continue
		i += 1
	return b.clone()

fn split_operands(b: Bytes) List[Bytes]:
	var out = List[Bytes]()
	n := b.length()
	if n == 0: return out
	var depth = 0
	var start = 0
	var i = 0
	while i < n:
		c := at(b, i)
		if c == 39:
			i = skip_char(b, i)
			continue
		if c == 91: depth += 1
		if c == 93 and depth > 0: depth -= 1
		if c == 44 and depth == 0:
			out.append(trim(b.view(start, i)))
			start = i + 1
		i += 1
	out.append(trim(b.view(start, n)))
	return out

type Terms:
	signs: List[Int] = []
	texts: List[String] = []

fn split_terms(b: Bytes) Terms:
	var t = Terms()
	n := b.length()
	var i = 0
	var sign = 1
	while i < n and is_ws(at(b, i)):
		i += 1
	if i < n and (at(b, i) == 43 or at(b, i) == 45):
		if at(b, i) == 45: sign = -1
		i += 1
	var start = i
	while true:
		while i < n:
			c := at(b, i)
			if c == 39:
				i = skip_char(b, i)
				continue
			if c == 43 or c == 45: break
			i += 1
		e := if i > n: n else: i
		t.signs.append(sign)
		t.texts.append(str(trim(b.view(start, e))))
		if i >= n: break
		sign = if at(b, i) == 45: -1 else: 1
		i += 1
		start = i
	return t

fn reg_index(s: String) Int:
	names := ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
	for i in 0..10:
		if names.get(i, "") == s: return i
	return -1

fn bad() Int!:
	return error(Error("BAD"))

fn escape_val(c: Int) Int:
	if c == 110: return 10
	if c == 116: return 9
	if c == 48: return 0
	if c == 92: return 92
	if c == 39: return 39
	if c == 34: return 34
	return -1

fn eval_term(t: String, resolve: Bool, labels: Map[String, Int], equs: Map[String, String], var visiting: List[String]) Int!:
	b := t.to_bytes()
	n := b.length()
	if n == 0: return bad()
	c := at(b, 0)
	if is_digit(c):
		var base = 10
		var s = 0
		if c == 48 and n > 1 and at(b, 1) == 120:
			base = 16
			s = 2
		else if c == 48 and n > 1 and at(b, 1) == 98:
			base = 2
			s = 2
		if s == n: return bad()
		var acc = 0
		for i in s..n:
			d := digit_val(at(b, i))
			if d < 0 or d >= base: return bad()
			acc = acc * base + d
			if acc > 8589934592: acc = 8589934592
		if acc > 4294967295: return error(Error("immediate out of range"))
		return ok(wrap(acc))
	if c == 39:
		if n == 3 and at(b, 2) == 39 and at(b, 1) != 39 and at(b, 1) != 92:
			return ok(at(b, 1))
		if n == 4 and at(b, 1) == 92 and at(b, 3) == 39:
			v := escape_val(at(b, 2))
			if v < 0: return bad()
			return ok(v)
		return bad()
	if not is_ident(b): return bad()
	if not resolve: return ok(0)
	if v := labels.get(t):
		return ok(v)
	if expr := equs.get(t):
		for name in visiting:
			if name == t: return error(Error("circular definition of '{t}'"))
		visiting.append(t.clone())
		r := eval_text(expr, labels, equs, var visiting)
		visiting.pop()
		return r
	return error(Error("undefined symbol '{t}'"))

fn eval_terms(signs: List[Int], texts: List[String], whole: String, labels: Map[String, Int], equs: Map[String, String], var visiting: List[String]) Int!:
	for k in 0..texts.length():
		r := eval_term(texts.get(k, ""), false, labels, equs, var visiting)
		if _v := r:
			continue
		else:
			e := r.err()
			if e.message == "BAD": return error(Error("invalid expression '{whole}'"))
			return error(e)
	var acc = 0
	for k in 0..texts.length():
		r := eval_term(texts.get(k, ""), true, labels, equs, var visiting)
		if v := r:
			acc = wrap(acc + signs.get(k, 1) * v)
		else:
			e := r.err()
			if e.message == "BAD": return error(Error("invalid expression '{whole}'"))
			return error(e)
	return ok(acc)

fn eval_text(text: String, labels: Map[String, Int], equs: Map[String, String], var visiting: List[String]) Int!:
	b := trim(text.to_bytes())
	t := split_terms(b)
	return eval_terms(t.signs, t.texts, str(b), labels, equs, var visiting)

type Operand:
	kind: Int = 0
	reg: Int = -1
	whole: String = ""
	signs: List[Int] = []
	texts: List[String] = []

type Instr:
	op: Int
	name: String
	line: Int
	a: Operand
	b: Operand

type DataItem:
	line: Int
	kind: Int
	exprs: List[String]
	bytes: List[Int]
	count: Int
	addr: Int
	fill: String
	has_fill: Bool

fn invalid_operand(text: String) Error:
	return Error("invalid operand '{text}'")

fn parse_operand(b: Bytes) Operand!:
	text := str(b)
	n := b.length()
	if n == 0: return error(invalid_operand(""))
	r := reg_index(text)
	if r >= 0: return ok(Operand(kind: 1, reg: r, whole: text))
	if at(b, 0) == 91:
		if n < 2 or at(b, n - 1) != 93: return error(invalid_operand(text))
		inner := trim(b.view(1, n - 1))
		if inner.length() == 0: return error(invalid_operand(text))
		t := split_terms(inner)
		var reg = -1
		var ns = List[Int]()
		var nt = List[String]()
		for k in 0..t.texts.length():
			txt := t.texts.get(k, "")
			if txt == "": return error(invalid_operand(text))
			ri := reg_index(txt)
			if ri >= 0:
				if t.signs.get(k, 1) < 0 or reg >= 0: return error(invalid_operand(text))
				reg = ri
			else:
				ns.append(t.signs.get(k, 1))
				nt.append(txt.clone())
		return ok(Operand(kind: 3, reg: reg, whole: str(inner), signs: ns, texts: nt))
	t := split_terms(b)
	return ok(Operand(kind: 2, whole: text, signs: t.signs, texts: t.texts))

fn mnemonics() Map[String, Int]:
	var m = Map[String, Int]()
	names := ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]
	for i in 0..names.length():
		m[names.get(i, "")] = i
	m["jz"] = 21
	m["jnz"] = 22
	return m

fn arity(op: Int) Int:
	if op == 28 or op == 32 or op == 33: return 0
	if op <= 12 or op == 17: return 2
	return 1

fn classes_ok(op: Int, a: Operand, b: Operand) Bool:
	if arity(op) == 0: return true
	if op == 0:
		if a.kind == 1: return true
		return a.kind == 3 and b.kind != 3
	if op <= 12: return a.kind == 1
	if op == 17: return a.kind == 1 and b.kind == 3
	if op == 18 or op == 30 or op == 31: return true
	if op >= 20 and op <= 27: return a.kind == 2
	return a.kind == 1

type Asm:
	labels: Map[String, Int] = Map[String, Int]()
	equs: Map[String, String] = Map[String, String]()
	instrs: List[Instr] = []
	items: List[DataItem] = []
	data_size: Int = 0
	in_data: Bool = false
	budget: Int = 100000
	main_pc: Int = -1
	mn: Map[String, Int] = mnemonics()

fn is_defined(asm: Asm, name: String) Bool:
	return asm.labels.get(name).is_some() or asm.equs.get(name).is_some()

fn parse_string(b: Bytes) List[Int]?:
	n := b.length()
	if n < 2 or at(b, 0) != 34 or at(b, n - 1) != 34: return none
	var out = List[Int]()
	var i = 1
	while i < n - 1:
		c := at(b, i)
		if c == 34: return none
		if c == 92:
			if i + 1 >= n - 1: return none
			v := escape_val(at(b, i + 1))
			if v < 0: return none
			out.append(v)
			i += 2
			continue
		out.append(c)
		i += 1
	return out

fn var Asm.define(name: String, value: Int) Unit!:
	if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
	if is_defined(self, name): return error(Error("duplicate symbol '{name}'"))
	self.labels[name.clone()] = value
	if name == "main" and not self.in_data: self.main_pc = value
	return ok(unit)

fn var Asm.directive(word: String, rest: Bytes, ln: Int) Unit!:
	if word == ".text" or word == ".data":
		if rest.length() > 0: return error(invalid_operand(str(rest)))
		self.in_data = word == ".data"
		return ok(unit)
	if word == ".equ":
		ops := split_operands(rest)
		if ops.length() != 2: return error(Error("wrong number of operands for '.equ'"))
		name := str(ops.get(0, rest))
		if not is_ident(ops.get(0, rest)): return error(invalid_operand(name))
		if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
		if is_defined(self, name): return error(Error("duplicate symbol '{name}'"))
		self.equs[name] = str(ops.get(1, rest))
		return ok(unit)
	if word == ".budget":
		text := str(rest)
		var okn = rest.length() > 0
		for i in 0..rest.length():
			if not is_digit(at(rest, i)): okn = false
		if not okn: return error(invalid_operand(text))
		v := text.parse_int().get(-1)
		if v < 1 or v > 10000000: return error(invalid_operand(text))
		self.budget = v
		return ok(unit)
	if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
		if not self.in_data: return error(Error("data directive in text section"))
		addr := self.data_size
		if word == ".word":
			ops := split_operands(rest)
			if ops.length() == 0: return error(Error("wrong number of operands for '.word'"))
			var ex = List[String]()
			for o in ops:
				ex.append(str(o))
			cnt := ex.length()
			if addr + cnt > 4096: return error(Error("data section too large"))
			self.items.append(DataItem(line: ln, kind: 0, exprs: ex, bytes: [], count: cnt, addr: addr, fill: "", has_fill: false))
			self.data_size = addr + cnt
			return ok(unit)
		if word == ".space":
			ops := split_operands(rest)
			if ops.length() < 1 or ops.length() > 2: return error(Error("wrong number of operands for '.space'"))
			ntext := str(ops.get(0, rest))
			var vis = List[String]()
			nv := eval_text(ntext, self.labels, self.equs, var vis)?
			if nv < 0: return error(invalid_operand(ntext))
			if addr + nv > 4096: return error(Error("data section too large"))
			hf := ops.length() == 2
			fl := if hf: str(ops.get(1, rest)) else: ""
			self.items.append(DataItem(line: ln, kind: 2, exprs: [], bytes: [], count: nv, addr: addr, fill: fl, has_fill: hf))
			self.data_size = addr + nv
			return ok(unit)
		parsed := parse_string(rest)
		if var bs = parsed:
			if word == ".asciz": bs.append(0)
			cnt := bs.length()
			if addr + cnt > 4096: return error(Error("data section too large"))
			self.items.append(DataItem(line: ln, kind: 1, exprs: [], bytes: bs, count: cnt, addr: addr, fill: "", has_fill: false))
			self.data_size = addr + cnt
			return ok(unit)
		return error(Error("invalid string"))
	return error(Error("unknown directive '{word}'"))

fn var Asm.instruction(word: String, rest: Bytes, ln: Int) Unit!:
	if self.in_data: return error(Error("instruction in data section"))
	opv := self.mn.get(word)
	if opv.is_none(): return error(Error("unknown mnemonic '{word}'"))
	op := opv.get(0)
	rawops := split_operands(rest)
	var ops = List[Operand]()
	for r in rawops:
		ops.append(parse_operand(r)?)
	if ops.length() != arity(op): return error(Error("wrong number of operands for '{word}'"))
	var a = Operand()
	var b = Operand()
	if ops.length() >= 1: a = ops.get(0, Operand())
	if ops.length() >= 2: b = ops.get(1, Operand())
	if not classes_ok(op, a, b): return error(Error("invalid operands for '{word}'"))
	self.instrs.append(Instr(op: op, name: word, line: ln, a: a, b: b))
	return ok(unit)

fn var Asm.line(raw: Bytes, ln: Int) Unit!:
	var b = trim(strip_comment(raw))
	while true:
		n := b.length()
		if n == 0 or not is_ident_start(at(b, 0)): break
		var j = 0
		while j < n and is_ident_char(at(b, j)):
			j += 1
		if at(b, j) != 58: break
		name := str(b.view(0, j))
		v := if self.in_data: self.data_size else: self.instrs.length()
		self.define(name, v)?
		b = trim(b.view(j + 1, n))
	n := b.length()
	if n == 0: return ok(unit)
	var e = 0
	while e < n and not is_ws(at(b, e)):
		e += 1
	word := str(b.view(0, e))
	rest := trim(b.view(e, n))
	if at(b, 0) == 46: return self.directive(word, rest, ln)
	return self.instruction(word, rest, ln)

type Prog:
	ops: List[Int] = []
	ak: List[Int] = []
	ar: List[Int] = []
	av: List[Int] = []
	bk: List[Int] = []
	br: List[Int] = []
	bv: List[Int] = []
	lines: List[Int] = []
	mem: List[Int] = []
	main_pc: Int = 0
	budget: Int = 0

fn eval_operand(o: Operand, asm: Asm) Int!:
	if o.kind == 1: return ok(0)
	var vis = List[String]()
	return eval_terms(o.signs, o.texts, o.whole, asm.labels, asm.equs, var vis)

fn at_line(ln: Int, e: Error) Error:
	return Error("asm error line {ln}: {e.message}")

fn link(asm: Asm) Prog!:
	var p = Prog()
	for i in 0..4096:
		p.mem.append(0)
	n := asm.instrs.length()
	nd := asm.items.length()
	var di = 0
	var ii = 0
	while di < nd or ii < n:
		take_data := if ii >= n: true else if di >= nd: false else: asm.items.get(di).line < asm.instrs.get(ii).line
		if take_data:
			item := asm.items.get(di)
			ln := item.line
			if item.kind == 0:
				for k in 0..item.count:
					var vis = List[String]()
					r := eval_text(item.exprs.get(k, ""), asm.labels, asm.equs, var vis)
					if v := r:
						p.mem[item.addr + k] = v
					else:
						return error(at_line(ln, r.err()))
			else if item.kind == 1:
				for k in 0..item.count:
					p.mem[item.addr + k] = item.bytes.get(k, 0)
			else:
				var v = 0
				if item.has_fill:
					var vis = List[String]()
					r := eval_text(item.fill, asm.labels, asm.equs, var vis)
					if x := r:
						v = x
					else:
						return error(at_line(ln, r.err()))
				for k in 0..item.count:
					p.mem[item.addr + k] = v
			di += 1
		else:
			ins := asm.instrs.get(ii)
			ra := eval_operand(ins.a, asm)
			var va = 0
			if x := ra:
				va = x
			else:
				return error(at_line(ins.line, ra.err()))
			rb := eval_operand(ins.b, asm)
			var vb = 0
			if x := rb:
				vb = x
			else:
				return error(at_line(ins.line, rb.err()))
			if ins.op >= 20 and ins.op <= 27:
				if va < 0 or va >= n: return error(at_line(ins.line, Error("invalid jump target")))
			p.ops.append(ins.op)
			p.ak.append(ins.a.kind)
			p.ar.append(ins.a.reg)
			p.av.append(va)
			p.bk.append(ins.b.kind)
			p.br.append(ins.b.reg)
			p.bv.append(vb)
			p.lines.append(ins.line)
			ii += 1
	p.main_pc = if asm.main_pc >= 0: asm.main_pc else: 0
	p.budget = asm.budget
	return ok(p)

type Vm:
	p: Prog
	regs: List[Int]
	z: Int = 0
	l: Int = 0
	pc: Int = 0
	steps: Int = 0
	trap: String = ""
	halted: Bool = false
	out: List[Int] = []
	inputs: List[Int] = []
	ip: Int = 0

fn var Vm.load(a: Int) Int:
	if a < 0 or a >= 4096:
		self.trap = "memory access out of range: {a}"
		return 0
	return self.p.mem.get(a, 0)

fn var Vm.store(a: Int, v: Int) Unit:
	if a < 0 or a >= 4096:
		self.trap = "memory access out of range: {a}"
		return
	self.p.mem[a] = v

fn Vm.addr(reg: Int, v: Int) Int:
	if reg >= 0: return wrap(self.regs.get(reg, 0) + v)
	return v

fn var Vm.read(k: Int, r: Int, v: Int) Int:
	if k == 1: return self.regs.get(r, 0)
	if k == 2: return v
	return self.load(self.addr(r, v))

fn var Vm.emit_text(s: String) Unit:
	for c in s.as_bytes().values():
		self.out.append(c.to_int())

fn var Vm.step() Unit:
	i := self.pc
	op := self.p.ops.get(i, 0)
	ak := self.p.ak.get(i, 0)
	ar := self.p.ar.get(i, 0)
	av := self.p.av.get(i, 0)
	bk := self.p.bk.get(i, 0)
	br := self.p.br.get(i, 0)
	bv := self.p.bv.get(i, 0)
	var next = i + 1
	if op == 0:
		v := self.read(bk, br, bv)
		if self.trap != "": return
		if ak == 1:
			self.regs[ar] = v
		else:
			self.store(self.addr(ar, av), v)
			if self.trap != "": return
	else if op <= 12:
		s := self.read(bk, br, bv)
		if self.trap != "": return
		d := self.regs.get(ar, 0)
		var res = 0
		if op == 1: res = wrap(d + s)
		else if op == 2: res = wrap(d - s)
		else if op == 3: res = wrap(d * s)
		else if op == 4 or op == 5:
			if s == 0:
				self.trap = "division by zero"
				return
			if op == 4: res = wrap(d / s)
			else: res = wrap(d % s)
		else if op == 6: res = bit_and(d, s)
		else if op == 7: res = bit_or(d, s)
		else if op == 8: res = bit_xor(d, s)
		else if op == 9: res = wrap(shift_left(d, bit_and(s, 31)))
		else if op == 10: res = wrap(shift_right_unsigned(bit_and(d, 4294967295), bit_and(s, 31)))
		else if op == 11: res = shift_right(d, bit_and(s, 31))
		else:
			self.z = if d == s: 1 else: 0
			self.l = if d < s: 1 else: 0
		if op != 12: self.regs[ar] = res
	else if op == 13: self.regs[ar] = wrap(0 - self.regs.get(ar, 0))
	else if op == 14: self.regs[ar] = 0 - self.regs.get(ar, 0) - 1
	else if op == 15: self.regs[ar] = wrap(self.regs.get(ar, 0) + 1)
	else if op == 16: self.regs[ar] = wrap(self.regs.get(ar, 0) - 1)
	else if op == 17: self.regs[ar] = self.addr(br, bv)
	else if op == 18:
		v := self.read(ak, ar, av)
		if self.trap != "": return
		if self.regs.get(8, 0) <= 0:
			self.trap = "stack overflow"
			return
		self.regs[8] = self.regs.get(8, 0) - 1
		self.store(self.regs.get(8, 0), v)
		if self.trap != "": return
	else if op == 19:
		if self.regs.get(8, 0) >= 4096:
			self.trap = "stack underflow"
			return
		v := self.load(self.regs.get(8, 0))
		if self.trap != "": return
		self.regs[8] = self.regs.get(8, 0) + 1
		self.regs[ar] = v
	else if op >= 20 and op <= 26:
		z := self.z == 1
		l := self.l == 1
		var take = false
		if op == 20: take = true
		else if op == 21: take = z
		else if op == 22: take = not z
		else if op == 23: take = l
		else if op == 24: take = l or z
		else if op == 25: take = not l and not z
		else: take = not l
		if take: next = av
	else if op == 27:
		if self.regs.get(8, 0) <= 0:
			self.trap = "stack overflow"
			return
		self.regs[8] = self.regs.get(8, 0) - 1
		self.store(self.regs.get(8, 0), i + 1)
		if self.trap != "": return
		next = av
	else if op == 28:
		if self.regs.get(8, 0) >= 4096:
			self.trap = "stack underflow"
			return
		v := self.load(self.regs.get(8, 0))
		if self.trap != "": return
		self.regs[8] = self.regs.get(8, 0) + 1
		next = v
	else if op == 29:
		if self.ip >= self.inputs.length():
			self.trap = "input exhausted"
			return
		self.regs[ar] = self.inputs.get(self.ip, 0)
		self.ip += 1
	else if op == 30:
		v := self.read(ak, ar, av)
		if self.trap != "": return
		self.emit_text("{v}\n")
	else if op == 31:
		v := self.read(ak, ar, av)
		if self.trap != "": return
		if v < 0 or v > 127:
			self.trap = "invalid character"
			return
		self.out.append(v)
	else if op == 32:
		self.halted = true
	self.steps += 1
	self.pc = next

fn var Vm.run() Unit:
	n := self.p.ops.length()
	while true:
		if self.steps == self.p.budget:
			self.trap = "budget exceeded"
			return
		if self.pc < 0 or self.pc >= n:
			self.trap = "pc out of range"
			return
		self.step()
		if self.trap != "" or self.halted: return

fn parse_inputs(lines: List[Bytes]) List[Int]:
	var out = List[Int]()
	for line in lines:
		n := line.length()
		var i = 0
		while i < n:
			while i < n and is_ws(at(line, i)):
				i += 1
			s := i
			while i < n and not is_ws(at(line, i)):
				i += 1
			if i == s: continue
			var j = s
			neg := at(line, s) == 45
			if neg: j += 1
			if j == i: continue
			var good = true
			var acc = 0
			for k in j..i:
				c := at(line, k)
				if not is_digit(c):
					good = false
					break
				acc = (acc * 10 + (c - 48)) % 4294967296
			if good:
				v := if neg: 0 - acc else: acc
				out.append(wrap(v))
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin(), none)?
	var lines = List[Bytes]()
	for part in data.split("\n".to_bytes()):
		var l = part
		if at(l, l.length() - 1) == 13: l = l.view(0, l.length() - 1).clone()
		lines.append(l)
	var src = List[Bytes]()
	var inp = List[Bytes]()
	var seen = false
	for l in lines:
		if seen:
			inp.append(l)
		else if str(l) == "====":
			seen = true
		else:
			src.append(l)
	var asm = Asm()
	for k in 0..src.length():
		r := asm.line(src.get(k, "".to_bytes()), k + 1)
		if not r.is_ok():
			print("{at_line(k + 1, r.err()).message}")
			return ok(unit)
	lr := link(asm)
	if not lr.is_ok():
		print(lr.err().message)
		return ok(unit)
	prog := lr?
	var regs = List[Int]()
	for i in 0..10:
		regs.append(0)
	regs[8] = 4096
	mpc := prog.main_pc
	var vm = Vm(p: prog, regs: regs)
	vm.pc = mpc
	vm.inputs = parse_inputs(inp)
	vm.run()
	var text = from_scalars(vm.out)?
	if vm.out.length() > 0 and vm.out.get(vm.out.length() - 1, 0) != 10:
		text = "{text}\n"
	print(text, end: "")
	if vm.trap == "":
		print("-- halted after {vm.steps} steps")
	else:
		ln := if vm.trap == "pc out of range": "-" else: "{vm.p.lines.get(vm.pc, 0)}"
		print("-- trap: {vm.trap} (pc={vm.pc} line={ln}) after {vm.steps} steps")
	r := vm.regs
	print("regs: r0={r.get(0, 0)} r1={r.get(1, 0)} r2={r.get(2, 0)} r3={r.get(3, 0)} r4={r.get(4, 0)} r5={r.get(5, 0)} r6={r.get(6, 0)} r7={r.get(7, 0)} sp={r.get(8, 0)} bp={r.get(9, 0)}")
	print("flags: Z={vm.z} L={vm.l}")
