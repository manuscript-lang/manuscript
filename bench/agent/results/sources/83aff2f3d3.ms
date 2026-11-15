import bit_and, bit_or, bit_xor, bit_not, shift_left, shift_right, shift_right_unsigned from "@std/math/math.ms"
import stdin, stdout_bytes from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"

fn w(x: Int) Int:
	v := bit_and(x, 4294967295)
	if v >= 2147483648: return v - 4294967296
	return v

fn at(s: String, i: Int) Int:
	if i < 0 or i >= s.length(): return -1
	return s.as_bytes().get(i).to_int()

fn is_ident_start(c: Int) Bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

fn is_ident_char(c: Int) Bool:
	return is_ident_start(c) or (c >= 48 and c <= 57) or c == 46

fn is_ident(s: String) Bool:
	n := s.length()
	if n == 0: return false
	b := s.as_bytes()
	if not is_ident_start(b.get(0).to_int()): return false
	for i in 1..n:
		if not is_ident_char(b.get(i).to_int()): return false
	return true

fn is_space(c: Int) Bool:
	return c == 32 or c == 9 or c == 13 or c == 10 or c == 11 or c == 12

fn reg_index(s: String) Int:
	if s == "sp": return 8
	if s == "bp": return 9
	if s.length() == 2 and s.starts_with("r"):
		c := at(s, 1)
		if c >= 48 and c <= 55: return c - 48
	return -1

fn esc(c: Int) Int:
	if c == 110: return 10
	if c == 116: return 9
	if c == 48: return 0
	if c == 92: return 92
	if c == 39: return 39
	if c == 34: return 34
	return -1

// end index (exclusive) of a char literal starting at i (s[i] == ')
fn char_end(b: Bytes, i: Int) Int:
	n := b.length()
	var j = i + 1
	if j < n and b.get(j).to_int() == 92: j += 2
	else: j += 1
	if j < n and b.get(j).to_int() == 39: j += 1
	return if j > n: n else: j

fn strip_comment(s: String) String:
	b := s.as_bytes()
	n := b.length()
	var i = 0
	while i < n:
		c := b.get(i).to_int()
		if c == 59: return s.view(0, i).clone()
		if c == 34:
			i += 1
			while i < n:
				d := b.get(i).to_int()
				if d == 92:
					i += 2
					continue
				if d == 34: break
				i += 1
			i += 1
			continue
		if c == 39:
			i = char_end(b, i)
			continue
		i += 1
	return s.clone()

type Term:
	neg: Bool
	text: String

fn split_terms(s: String) List[Term]:
	b := s.as_bytes()
	n := b.length()
	var out = List[Term]()
	var neg = false
	var i = 0
	if n > 0:
		c0 := b.get(0).to_int()
		if c0 == 43 or c0 == 45:
			neg = c0 == 45
			i = 1
	while true:
		start := i
		var j = i
		while j < n:
			c := b.get(j).to_int()
			if c == 43 or c == 45: break
			if c == 39:
				j = char_end(b, j)
				continue
			j += 1
		out.append(Term(neg, s.view(start, j).trim().clone()))
		if j >= n: break
		neg = b.get(j).to_int() == 45
		i = j + 1
	return out

fn split_operands(s: String) List[String]:
	var out = List[String]()
	if s == "": return out
	b := s.as_bytes()
	n := b.length()
	var depth = 0
	var start = 0
	var j = 0
	while j < n:
		c := b.get(j).to_int()
		if c == 39:
			j = char_end(b, j)
			continue
		if c == 91: depth += 1
		else if c == 93:
			if depth > 0: depth -= 1
		else if c == 44 and depth == 0:
			out.append(s.view(start, j).trim().clone())
			start = j + 1
		j += 1
	out.append(s.view(start, n).trim().clone())
	return out

type PT:
	sym: String
	val: Int

fn bad_expr(whole: String) Error:
	return Error("invalid expression '{whole}'")

fn parse_term(text: String, whole: String) PT!:
	n := text.length()
	if n == 0: return error(bad_expr(whole))
	b := text.as_bytes()
	c0 := b.get(0).to_int()
	if c0 >= 48 and c0 <= 57:
		var base = 10
		var start = 0
		if n > 2 and c0 == 48:
			c1 := b.get(1).to_int()
			if c1 == 120:
				base = 16
				start = 2
			else if c1 == 98:
				base = 2
				start = 2
		var val = 0
		var over = false
		for i in start..n:
			c := b.get(i).to_int()
			var d = -1
			if c >= 48 and c <= 57: d = c - 48
			else if c >= 97 and c <= 102: d = c - 87
			else if c >= 65 and c <= 70: d = c - 55
			if d < 0 or d >= base: return error(bad_expr(whole))
			val = val * base + d
			if val > 4294967295:
				over = true
				val = 4294967296
		if over: return error(Error("immediate out of range"))
		return ok(PT("", w(val)))
	if c0 == 39:
		if n == 3:
			c := b.get(1).to_int()
			if c != 92 and c != 39 and b.get(2).to_int() == 39: return ok(PT("", c))
			return error(bad_expr(whole))
		if n == 4 and b.get(1).to_int() == 92 and b.get(3).to_int() == 39:
			e := esc(b.get(2).to_int())
			if e >= 0: return ok(PT("", e))
		return error(bad_expr(whole))
	if is_ident(text): return ok(PT(text.clone(), 0))
	return error(bad_expr(whole))

type Syms:
	labels: Map[String, Int] = Map[String, Int]()
	equs: Map[String, String] = Map[String, String]()
	cache: Map[String, Int] = Map[String, Int]()
	busy: Set[String] = Set[String]()

fn var Syms.lookup(name: String) Int!:
	if v := self.labels.get(name): return ok(v)
	if v := self.cache.get(name): return ok(v)
	if expr := self.equs.get(name):
		if self.busy.contains(name): return error(Error("circular definition of '{name}'"))
		self.busy.add(name.clone())
		e := expr.clone()
		v := self.eval_expr(e)?
		self.busy.remove(name.clone())
		self.cache[name.clone()] = v
		return ok(v)
	return error(Error("undefined symbol '{name}'"))

fn var Syms.eval_expr(whole: String) Int!:
	shown := whole.trim()
	terms := split_terms(shown)
	var pts = List[PT]()
	for t in terms:
		pts.append(parse_term(t.text, shown)?)
	var total = 0
	for i in 0..terms.length():
		p := pts.get(i, PT("", 0))
		var v = p.val
		if p.sym != "": v = self.lookup(p.sym)?
		if terms.get(i, Term(false, "")).neg: total = w(total - v)
		else: total = w(total + v)
	return ok(total)

type Operand:
	kind: Int = 0
	reg: Int = -1
	text: String = ""
	terms: List[Term] = List[Term]()

fn bad_op(text: String) Error:
	return Error("invalid operand '{text}'")

fn parse_operand(text: String) Operand!:
	if text == "": return error(bad_op(text))
	r := reg_index(text)
	if r >= 0: return ok(Operand(kind: 1, reg: r))
	n := text.length()
	if at(text, 0) == 91:
		if n < 2 or at(text, n - 1) != 93: return error(bad_op(text))
		inner := text.view(1, n - 1)
		var reg = -1
		var exprs = List[Term]()
		for t in split_terms(inner.trim()):
			if t.text == "": return error(bad_op(text))
			ri := reg_index(t.text)
			if ri >= 0:
				if t.neg or reg >= 0: return error(bad_op(text))
				reg = ri
			else:
				exprs.append(Term(t.neg, t.text.clone()))
		return ok(Operand(kind: 3, reg: reg, terms: exprs))
	return ok(Operand(kind: 2, text: text.clone()))

type Instr:
	op: Int
	line: Int
	nops: Int
	a: Operand
	b: Operand

type Task:
	kind: Int
	line: Int
	a: Int
	n: Int
	expr: String

type St:
	syms: Syms = Syms()
	mem: List[Int] = List[Int]()
	dlen: Int = 0
	in_data: Bool = false
	instrs: List[Instr] = List[Instr]()
	tasks: List[Task] = List[Task]()
	budget: Int = 100000
	main_pc: Int = -1
	line: Int = 0
	mn: Map[String, Int] = Map[String, Int]()

fn arity(op: Int) Int:
	if op <= 12: return 2
	if op == 17: return 2
	if op == 28 or op == 32 or op == 33: return 0
	return 1

fn allowed(op: Int, pos: Int, k: Int, k0: Int) Bool:
	// k: kind of this operand (1 R, 2 I, 3 M), k0: kind of first operand
	if op == 0:
		if pos == 0: return true
		if k0 == 3: return k != 3
		return true
	if op <= 12:
		if pos == 0: return k == 1
		return true
	if op <= 16: return k == 1
	if op == 17:
		if pos == 0: return k == 1
		return k == 3
	if op == 18: return true
	if op == 19: return k == 1
	if op <= 27: return k == 2
	if op == 29: return k == 1
	return true

fn parse_string(text: String) List[Int]!:
	n := text.length()
	if n < 2 or at(text, 0) != 34 or at(text, n - 1) != 34: return error(Error("invalid string"))
	var out = List[Int]()
	var i = 1
	while i < n - 1:
		c := at(text, i)
		if c == 34: return error(Error("invalid string"))
		if c == 92:
			if i + 1 >= n - 1: return error(Error("invalid string"))
			e := esc(at(text, i + 1))
			if e < 0: return error(Error("invalid string"))
			out.append(e)
			i += 2
		else:
			out.append(c)
			i += 1
	return ok(out)

fn var St.add_data_check(n: Int) Unit!:
	if self.dlen + n > 4096: return error(Error("data section too large"))
	return ok(unit)

fn var St.define(name: String) Unit!:
	if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
	if self.syms.labels.get(name).is_some() or self.syms.equs.get(name).is_some():
		return error(Error("duplicate symbol '{name}'"))
	return ok(unit)

fn var St.directive(word: String, rest: String) Unit!:
	if word == ".text" or word == ".data":
		if rest != "": return error(bad_op(rest))
		self.in_data = word == ".data"
		return ok(unit)
	if word == ".budget":
		v := rest.parse_int()
		if x := v:
			if x >= 1 and x <= 10000000 and at(rest, 0) != 43:
				self.budget = x
				return ok(unit)
		return error(bad_op(rest))
	if word == ".equ":
		ops := split_operands(rest)
		if rest == "" or ops.length() != 2: return error(Error("wrong number of operands for '.equ'"))
		name := ops.get(0, "")
		if not is_ident(name): return error(bad_op(name))
		self.define(name)?
		self.syms.equs[name.clone()] = ops.get(1, "")
		return ok(unit)
	if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
		if not self.in_data: return error(Error("data directive in text section"))
		if word == ".word":
			ops := split_operands(rest)
			if ops.length() < 1: return error(Error("wrong number of operands for '.word'"))
			self.add_data_check(ops.length())?
			for o in ops:
				self.tasks.append(Task(0, self.line, self.dlen, 1, o.clone()))
				self.dlen += 1
			return ok(unit)
		if word == ".space":
			ops := split_operands(rest)
			if ops.length() < 1 or ops.length() > 2: return error(Error("wrong number of operands for '.space'"))
			nraw := ops.get(0, "")
			n := self.syms.eval_expr(nraw)?
			if n < 0: return error(bad_op(nraw))
			self.add_data_check(n)?
			fill := if ops.length() == 2: ops.get(1, "") else: "0"
			self.tasks.append(Task(1, self.line, self.dlen, n, fill))
			self.dlen += n
			return ok(unit)
		vals := parse_string(rest)?
		extra := if word == ".asciz": 1 else: 0
		self.add_data_check(vals.length() + extra)?
		for v in vals:
			self.mem.set(self.dlen, v)
			self.dlen += 1
		if extra == 1: self.dlen += 1
		return ok(unit)
	return error(Error("unknown directive '{word}'"))

fn var St.instruction(word: String, rest: String) Unit!:
	if self.in_data: return error(Error("instruction in data section"))
	op := self.mn.get(word).get(-1)
	if op < 0: return error(Error("unknown mnemonic '{word}'"))
	texts := split_operands(rest)
	var ops = List[Operand]()
	for t in texts:
		ops.append(parse_operand(t)?)
	if ops.length() != arity(op): return error(Error("wrong number of operands for '{word}'"))
	var k0 = 0
	for i in 0..ops.length():
		k := ops.get(i, Operand()).kind
		if i == 0: k0 = k
		if not allowed(op, i, k, k0): return error(Error("invalid operands for '{word}'"))
	var a = Operand()
	var b = Operand()
	if ops.length() > 0: a = ops.replace(0, Operand())
	if ops.length() > 1: b = ops.replace(1, Operand())
	self.instrs.append(Instr(op, self.line, texts.length(), a, b))
	self.tasks.append(Task(2, self.line, self.instrs.length() - 1, 0, ""))
	return ok(unit)

fn var St.process(raw: String) Unit!:
	var rest = strip_comment(raw).trim().clone()
	while true:
		if rest.length() == 0: return ok(unit)
		b := rest.as_bytes()
		if not is_ident_start(b.get(0).to_int()): break
		var i = 1
		while i < b.length() and is_ident_char(b.get(i).to_int()): i += 1
		if i >= b.length() or b.get(i).to_int() != 58: break
		name := rest.view(0, i).clone()
		self.define(name)?
		if self.in_data: self.syms.labels[name.clone()] = self.dlen
		else:
			self.syms.labels[name.clone()] = self.instrs.length()
			if name == "main": self.main_pc = self.instrs.length()
		rest = rest.view(i + 1, rest.length()).trim()
	var j = 0
	while j < rest.length() and not is_space(at(rest, j)): j += 1
	word := rest.view(0, j).clone()
	args := rest.view(j, rest.length()).trim().clone()
	if word.starts_with("."): return self.directive(word, args)
	return self.instruction(word, args)

fn var St.eval_mem(o: Operand) Int!:
	var total = 0
	for t in o.terms:
		v := self.syms.eval_expr(t.text)?
		if t.neg: total = w(total - v)
		else: total = w(total + v)
	return ok(total)

fn var St.pass2(var iop: List[Int], var iline: List[Int], var kk: List[Int], var rr: List[Int], var vv: List[Int]) Unit!:
	for t in self.tasks.clone():
		self.line = t.line
		if t.kind == 0:
			v := self.syms.eval_expr(t.expr)?
			self.mem.set(t.a, v)
		else if t.kind == 1:
			v := self.syms.eval_expr(t.expr)?
			for i in 0..t.n: self.mem.set(t.a + i, v)
		else:
			ins := self.instrs.get(t.a, Instr(0, 0, 0, Operand(), Operand()))
			iop.append(ins.op)
			iline.append(ins.line)
			for pos in 0..2:
				o := if pos == 0: ins.a else: ins.b
				if o.kind == 1:
					kk.append(1)
					rr.append(o.reg)
					vv.append(0)
				else if o.kind == 2:
					v := self.syms.eval_expr(o.text)?
					if ins.op >= 20 and ins.op <= 27:
						if v < 0 or v >= self.instrs.length(): return error(Error("invalid jump target"))
					kk.append(2)
					rr.append(-1)
					vv.append(v)
				else if o.kind == 3:
					v := self.eval_mem(o)?
					kk.append(3)
					rr.append(o.reg)
					vv.append(v)
				else:
					kk.append(0)
					rr.append(-1)
					vv.append(0)
	return ok(unit)

fn mnemonics() Map[String, Int]:
	var m = Map[String, Int]()
	names := ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]
	for i in 0..names.length():
		m[names.get(i, "")] = i
	m["jz"] = 21
	m["jnz"] = 22
	return m

fn main() Unit!:
	raw := read_all(stdin(), none)?
	text := raw.decode_utf8().get("")
	lines := text.split("\n")
	var src = List[String]()
	var inp = ""
	var seen = false
	for l0 in lines:
		l := if l0.ends_with("\r"): l0.view(0, l0.length() - 1) else: l0.view(0, l0.length())
		if seen:
			inp = inp + l + "\n"
		else if l == "====":
			seen = true
		else:
			src.append(l.clone())
	var st = St()
	for i in 0..4096: st.mem.append(0)
	st.mn = mnemonics()
	for i in 0..src.length():
		st.line = i + 1
		r := st.process(src.get(i, ""))
		if _x := r: continue
		else:
			print("asm error line {st.line}: {r.err().message}")
			return ok(unit)
	var iop = List[Int]()
	var iline = List[Int]()
	var kk = List[Int]()
	var rr = List[Int]()
	var vv = List[Int]()
	r2 := st.pass2(var iop, var iline, var kk, var rr, var vv)
	if _x := r2:
		unit
	else:
		print("asm error line {st.line}: {r2.err().message}")
		return ok(unit)
	run(st.mem, iop, iline, kk, rr, vv, st.main_pc, st.budget, inp)?
	return ok(unit)


fn parse_inputs(text: String) List[Int]:
	b := text.as_bytes()
	n := b.length()
	var out = List[Int]()
	var i = 0
	while i < n:
		while i < n and is_space(b.get(i).to_int()): i += 1
		start := i
		while i < n and not is_space(b.get(i).to_int()): i += 1
		if i == start: continue
		var j = start
		neg := b.get(j).to_int() == 45
		if neg: j += 1
		if j >= i: continue
		var ok_tok = true
		var v = 0
		for k in j..i:
			c := b.get(k).to_int()
			if c < 48 or c > 57:
				ok_tok = false
				break
			v = (v * 10 + (c - 48)) % 4294967296
		if ok_tok: out.append(w(if neg: -v else: v))
	return out

type VM:
	regs: List[Int]
	mem: List[Int]
	trap: String = ""
	out: BytesBuilder = BytesBuilder()
	last: Int = 10
	any_out: Bool = false

fn var VM.rd(k: Int, r: Int, v: Int) Int:
	if k == 1: return self.regs.get(r, 0)
	if k == 2: return v
	var addr = v
	if r >= 0: addr = w(self.regs.get(r, 0) + v)
	if addr < 0 or addr >= 4096:
		self.trap = "memory access out of range: {addr}"
		return 0
	return self.mem.get(addr, 0)

fn var VM.wr(addr: Int, val: Int) Unit:
	if addr < 0 or addr >= 4096:
		self.trap = "memory access out of range: {addr}"
		return
	self.mem.set(addr, val)

fn var VM.emit(s: String) Unit:
	b := s.as_bytes()
	self.out.append_bytes(b)
	if b.length() > 0:
		self.last = b.get(b.length() - 1).to_int()

fn var VM.emit_byte(c: Int) Unit:
	self.out.append(c.to_uint8().get(0))
	self.last = c

fn run(mem: List[Int], iop: List[Int], iline: List[Int], kk: List[Int], rr: List[Int], vv: List[Int], main_pc: Int, budget: Int, input: String) Unit!:
	var regs = List[Int]()
	for i in 0..10: regs.append(0)
	regs.set(8, 4096)
	var vm = VM(regs, mem.clone())
	inputs := parse_inputs(input)
	var in_idx = 0
	n := iop.length()
	var pc = if main_pc >= 0: main_pc else: 0
	var steps = 0
	var z = false
	var l = false
	var halted = false
	while true:
		if pc < 0 or pc >= n:
			vm.trap = "pc out of range"
			break
		if steps == budget:
			vm.trap = "budget exceeded"
			break
		op := iop.get(pc, 0)
		k1 := kk.get(2 * pc, 0)
		r1 := rr.get(2 * pc, -1)
		v1 := vv.get(2 * pc, 0)
		k2 := kk.get(2 * pc + 1, 0)
		r2 := rr.get(2 * pc + 1, -1)
		v2 := vv.get(2 * pc + 1, 0)
		var next = pc + 1
		if op == 0:
			s := vm.rd(k2, r2, v2)
			if vm.trap != "": break
			if k1 == 1: vm.regs.set(r1, s)
			else:
				var addr = v1
				if r1 >= 0: addr = w(vm.regs.get(r1, 0) + v1)
				vm.wr(addr, s)
		else if op <= 12:
			s := vm.rd(k2, r2, v2)
			if vm.trap != "": break
			x := vm.regs.get(r1, 0)
			if op == 1: vm.regs.set(r1, w(x + s))
			else if op == 2: vm.regs.set(r1, w(x - s))
			else if op == 3: vm.regs.set(r1, w(x * s))
			else if op == 4 or op == 5:
				if s == 0:
					vm.trap = "division by zero"
					break
				if op == 4: vm.regs.set(r1, w(x / s))
				else: vm.regs.set(r1, w(x % s))
			else if op == 6: vm.regs.set(r1, bit_and(x, s))
			else if op == 7: vm.regs.set(r1, bit_or(x, s))
			else if op == 8: vm.regs.set(r1, bit_xor(x, s))
			else if op == 9: vm.regs.set(r1, w(shift_left(x, bit_and(s, 31))))
			else if op == 10: vm.regs.set(r1, w(shift_right_unsigned(bit_and(x, 4294967295), bit_and(s, 31))))
			else if op == 11: vm.regs.set(r1, shift_right(x, bit_and(s, 31)))
			else:
				z = x == s
				l = x < s
		else if op == 13: vm.regs.set(r1, w(-vm.regs.get(r1, 0)))
		else if op == 14: vm.regs.set(r1, bit_not(vm.regs.get(r1, 0)))
		else if op == 15: vm.regs.set(r1, w(vm.regs.get(r1, 0) + 1))
		else if op == 16: vm.regs.set(r1, w(vm.regs.get(r1, 0) - 1))
		else if op == 17:
			var addr = v2
			if r2 >= 0: addr = w(vm.regs.get(r2, 0) + v2)
			vm.regs.set(r1, addr)
		else if op == 18 or op == 27:
			var s = next
			if op == 18:
				s = vm.rd(k1, r1, v1)
				if vm.trap != "": break
			sp := vm.regs.get(8, 0)
			if sp <= 0:
				vm.trap = "stack overflow"
				break
			vm.regs.set(8, sp - 1)
			vm.wr(sp - 1, s)
			if vm.trap != "": break
			if op == 27: next = v1
		else if op == 19 or op == 28:
			sp := vm.regs.get(8, 0)
			if sp >= 4096:
				vm.trap = "stack underflow"
				break
			s := vm.rd(3, -1, sp)
			if vm.trap != "": break
			vm.regs.set(8, sp + 1)
			if op == 19: vm.regs.set(r1, s)
			else: next = s
		else if op >= 20 and op <= 26:
			var take = true
			if op == 21: take = z
			else if op == 22: take = not z
			else if op == 23: take = l
			else if op == 24: take = l or z
			else if op == 25: take = not l and not z
			else if op == 26: take = not l
			if take: next = v1
		else if op == 29:
			if in_idx >= inputs.length():
				vm.trap = "input exhausted"
				break
			vm.regs.set(r1, inputs.get(in_idx, 0))
			in_idx += 1
		else if op == 30:
			s := vm.rd(k1, r1, v1)
			if vm.trap != "": break
			vm.emit("{s}\n")
		else if op == 31:
			s := vm.rd(k1, r1, v1)
			if vm.trap != "": break
			if s < 0 or s > 127:
				vm.trap = "invalid character"
				break
			vm.emit_byte(s)
		else if op == 32:
			steps += 1
			halted = true
			break
		steps += 1
		pc = next
	if vm.last != 10:
		vm.emit_byte(10)
	var o = stdout_bytes()
	o.write(vm.out.build())?
	var tail = ""
	if halted:
		tail = "-- halted after {steps} steps\n"
	else:
		line := if vm.trap == "pc out of range": "-" else: "{iline.get(pc, 0)}"
		tail = "-- trap: {vm.trap} (pc={pc} line={line}) after {steps} steps\n"
	reg_line := "regs: r0={vm.regs.get(0, 0)} r1={vm.regs.get(1, 0)} r2={vm.regs.get(2, 0)} r3={vm.regs.get(3, 0)} r4={vm.regs.get(4, 0)} r5={vm.regs.get(5, 0)} r6={vm.regs.get(6, 0)} r7={vm.regs.get(7, 0)} sp={vm.regs.get(8, 0)} bp={vm.regs.get(9, 0)}\n"
	zf := if z: 1 else: 0
	lf := if l: 1 else: 0
	o.write("{tail}{reg_line}flags: Z={zf} L={lf}\n".as_bytes())?
	return ok(unit)
