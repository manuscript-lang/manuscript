import from_scalars from "@std/string.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import bit_and, bit_not, shift_left, shift_right, shift_right_unsigned, bit_or, bit_xor from "@std/math/math.ms"

fn bl(s: String) List[Int]: s.as_bytes().values().map(fn x: x.to_int())

fn sub(s: String, a: Int, b: Int) String: s.view(a, b).clone()

fn wrap(x: Int) Int:
	m := bit_and(x, 4294967295)
	if m >= 2147483648: return m - 4294967296
	return m

fn is_digit(c: Int) Bool: c >= 48 and c <= 57
fn is_ident_start(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
fn is_ident_char(c: Int) Bool: is_ident_start(c) or is_digit(c) or c == 46

fn digit_val(c: Int) Int:
	if is_digit(c): return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return -1

fn esc(c: Int) Int:
	if c == 110: return 10
	if c == 116: return 9
	if c == 48: return 0
	if c == 92: return 92
	if c == 39: return 39
	if c == 34: return 34
	return -1

fn reg_index(s: String) Int:
	if s == "sp": return 8
	if s == "bp": return 9
	if s.length() == 2 and s.starts_with("r"):
		c := s.as_bytes().get(1).to_int()
		if c >= 48 and c <= 55: return c - 48
	return -1

fn is_ident(s: String) Bool:
	b := bl(s)
	if b.length() == 0: return false
	if not is_ident_start(b.get(0, 0)): return false
	for c in b:
		if not is_ident_char(c): return false
	return true

// index after a well-formed char literal starting at i, else -1
fn char_lit_end(b: List[Int], i: Int) Int:
	n := b.length()
	var j = i + 1
	if j >= n: return -1
	if b.get(j, 0) == 92:
		j += 2
	else:
		j += 1
	if j < n and b.get(j, 0) == 39: return j + 1
	return -1

fn strip_comment(s: String) String:
	b := bl(s)
	n := b.length()
	var i = 0
	while i < n:
		c := b.get(i, 0)
		if c == 59: return sub(s, 0, i)
		if c == 34:
			var j = i + 1
			var closed = false
			while j < n:
				d := b.get(j, 0)
				if d == 92:
					j += 2
					continue
				if d == 34:
					closed = true
					break
				j += 1
			if not closed: return s.clone()
			i = j + 1
			continue
		if c == 39:
			e := char_lit_end(b, i)
			if e > 0:
				i = e
				continue
		i += 1
	return s.clone()

fn split_ops(s: String) List[String]:
	t := s.trim()
	var out = List[String]()
	if t.length() == 0: return out
	b := bl(t)
	n := b.length()
	var depth = 0
	var start = 0
	var i = 0
	while i < n:
		c := b.get(i, 0)
		if c == 39:
			e := char_lit_end(b, i)
			if e > 0:
				i = e
				continue
		else if c == 91:
			depth += 1
		else if c == 93:
			if depth > 0: depth -= 1
		else if c == 44 and depth == 0:
			out.append(sub(t, start, i).trim())
			start = i + 1
		i += 1
	out.append(sub(t, start, n).trim())
	return out

type Term:
	sign: Int
	text: String

fn split_terms(s: String) List[Term]:
	t := s.trim()
	b := bl(t)
	n := b.length()
	var out = List[Term]()
	var i = 0
	var sign = 1
	if n > 0 and (b.get(0, 0) == 43 or b.get(0, 0) == 45):
		if b.get(0, 0) == 45: sign = -1
		i = 1
	var start = i
	while i < n:
		c := b.get(i, 0)
		if c == 39:
			e := char_lit_end(b, i)
			if e > 0:
				i = e
				continue
		if c == 43 or c == 45:
			out.append(Term(sign, sub(t, start, i).trim()))
			sign = if c == 45: -1 else: 1
			start = i + 1
		i += 1
	out.append(Term(sign, sub(t, start, n).trim()))
	return out

type Opd:
	kind: Int
	reg: Int
	text: String

type PInst:
	op: Int
	line: Int
	ops: List[Opd]

type Inst:
	op: Int
	line: Int
	ak: Int
	ar: Int
	av: Int
	bk: Int
	br: Int
	bv: Int

type Item:
	kind: Int
	line: Int
	idx: Int
	count: Int
	texts: List[String]

fn mnemonic_table() Map[String, Int]:
	var m = Map[String, Int]()
	names := ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]
	for i in 0..names.length():
		m[names.get(i, "")] = i
	m["jz"] = 21
	m["jnz"] = 22
	return m

fn expected_count(op: Int) Int:
	if op <= 12 or op == 17: return 2
	if op == 28 or op == 32 or op == 33: return 0
	return 1

fn classes_ok(op: Int, ops: List[Opd]) Bool:
	if op == 0:
		a := ops.get(0).kind
		b := ops.get(1).kind
		if a == 0: return true
		if a == 2: return b != 2
		return false
	if op <= 12: return ops.get(0).kind == 0
	if op == 17: return ops.get(0).kind == 0 and ops.get(1).kind == 2
	if op == 13 or op == 14 or op == 15 or op == 16 or op == 19 or op == 29: return ops.get(0).kind == 0
	if op == 18 or op == 30 or op == 31: return true
	if op >= 20 and op <= 27: return ops.get(0).kind == 1
	return true

type Asm:
	labels: Map[String, Int] = Map[String, Int]()
	equs: Map[String, String] = Map[String, String]()
	memo: Map[String, Int] = Map[String, Int]()
	busy: Set[String] = Set[String]()
	data: List[Int] = List[Int]()
	items: List[Item] = List[Item]()
	insts: List[PInst] = List[PInst]()
	code: List[Inst] = List[Inst]()
	section: Int = 0
	budget: Int = 100000
	main_idx: Int = -1
	cur: Int = 0

fn Asm.fail(msg: String) Error: Error("asm error line {self.cur}: {msg}")

fn var Asm.eval_term(t: String, whole: String) Int!:
	b := bl(t)
	n := b.length()
	bad := self.fail("invalid expression '{whole}'")
	if n == 0: return error(bad)
	c := b.get(0, 0)
	if is_digit(c):
		var base = 10
		var pos = 0
		if n >= 2 and c == 48 and b.get(1, 0) == 120:
			base = 16
			pos = 2
		else if n >= 2 and c == 48 and b.get(1, 0) == 98:
			base = 2
			pos = 2
		if pos >= n: return error(bad)
		var v = 0
		var big = false
		while pos < n:
			d := digit_val(b.get(pos, 0))
			if d < 0 or d >= base: return error(bad)
			v = v * base + d
			if v > 4294967295:
				big = true
				v = 4294967296
			pos += 1
		if big: return error(self.fail("immediate out of range"))
		return ok(wrap(v))
	if c == 39:
		if n < 3 or b.get(n - 1, 0) != 39: return error(bad)
		if n == 3:
			d := b.get(1, 0)
			if d == 39 or d == 92: return error(bad)
			return ok(d)
		if n == 4 and b.get(1, 0) == 92:
			e := esc(b.get(2, 0))
			if e < 0: return error(bad)
			return ok(e)
		return error(bad)
	if is_ident_start(c):
		for d in b:
			if not is_ident_char(d): return error(bad)
		if v := self.labels.get(t): return ok(v)
		if self.equs.get(t).is_some():
			if m := self.memo.get(t): return ok(m)
			if self.busy.contains(t): return error(self.fail("circular definition of '{t}'"))
			ex := self.equs.get_or(t, "")
			self.busy.add(t.clone())
			r := self.eval_expr(ex, false)?
			self.busy.remove(t.clone())
			self.memo[t.clone()] = r
			return ok(r)
		return error(self.fail("undefined symbol '{t}'"))
	return error(bad)

fn var Asm.eval_expr(text: String, skip_regs: Bool) Int!:
	terms := split_terms(text)
	whole := text.trim()
	var acc = 0
	for t in terms:
		if skip_regs and reg_index(t.text) >= 0: continue
		v := self.eval_term(t.text, whole)?
		acc = wrap(acc + t.sign * v)
	return ok(acc)

fn Asm.parse_opd(text: String) Opd!:
	t := text.trim()
	bad := Error("asm error line {self.cur}: invalid operand '{t}'")
	if t.length() == 0: return error(bad)
	r := reg_index(t)
	if r >= 0: return ok(Opd(0, r, ""))
	b := bl(t)
	n := b.length()
	if b.get(0, 0) == 91:
		if n < 2 or b.get(n - 1, 0) != 93: return error(bad)
		inner := sub(t, 1, n - 1)
		for c in bl(inner):
			if c == 91 or c == 93: return error(bad)
		if inner.trim().length() == 0: return error(bad)
		var base = -1
		for term in split_terms(inner):
			if term.text.length() == 0: return error(bad)
			ri := reg_index(term.text)
			if ri >= 0:
				if term.sign < 0 or base >= 0: return error(bad)
				base = ri
		return ok(Opd(2, base, inner))
	return ok(Opd(1, -1, t))

fn var Asm.define(name: String, is_label: Bool, value: Int, expr: String) Unit!:
	if reg_index(name) >= 0: return error(self.fail("reserved name '{name}'"))
	if self.labels.get(name).is_some() or self.equs.get(name).is_some():
		return error(self.fail("duplicate symbol '{name}'"))
	if is_label:
		self.labels[name] = value
	else:
		self.equs[name] = expr.clone()

fn var Asm.check_size(extra: Int) Unit!:
	if self.data.length() + extra > 4096: return error(self.fail("data section too large"))

fn var Asm.directive(word: String, rest: String) Unit!:
	if word == ".text" or word == ".data":
		if rest.length() > 0: return error(self.fail("invalid operand '{rest}'"))
		self.section = if word == ".text": 0 else: 1
		return ok(unit)
	if word == ".budget":
		b := bl(rest)
		var okn = b.length() >= 1 and b.length() <= 8
		var v = 0
		for c in b:
			if not is_digit(c): okn = false
			else: v = v * 10 + (c - 48)
		if not okn or v < 1 or v > 10000000: return error(self.fail("invalid operand '{rest}'"))
		self.budget = v
		return ok(unit)
	if word == ".equ":
		ops := split_ops(rest)
		if ops.length() != 2: return error(self.fail("wrong number of operands for '.equ'"))
		name := ops.get(0, "")
		if not is_ident(name): return error(self.fail("invalid operand '{name}'"))
		self.define(name, false, 0, ops.get(1, ""))?
		return ok(unit)
	if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
		if self.section == 0: return error(self.fail("data directive in text section"))
		if word == ".word":
			ops := split_ops(rest)
			if ops.length() == 0: return error(self.fail("wrong number of operands for '.word'"))
			self.check_size(ops.length())?
			self.items.append(Item(1, self.cur, self.data.length(), ops.length(), ops.clone()))
			for _i in 0..ops.length():
				self.data.append(0)
			return ok(unit)
		if word == ".space":
			ops := split_ops(rest)
			if ops.length() < 1 or ops.length() > 2: return error(self.fail("wrong number of operands for '.space'"))
			n := self.eval_expr(ops.get(0, ""), false)?
			if n < 0: return error(self.fail("invalid operand '{ops.get(0, "")}'"))
			self.check_size(n)?
			if ops.length() == 2:
				self.items.append(Item(2, self.cur, self.data.length(), n, [ops.get(1, "")]))
			for _i in 0..n:
				self.data.append(0)
			return ok(unit)
		// ascii / asciz
		t := rest.trim()
		b := bl(t)
		n := b.length()
		bad := Error("asm error line {self.cur}: invalid string")
		if n < 2 or b.get(0, 0) != 34: return error(bad)
		var vals = List[Int]()
		var i = 1
		var closed = false
		while i < n:
			c := b.get(i, 0)
			if c == 92:
				if i + 1 >= n: return error(bad)
				e := esc(b.get(i + 1, 0))
				if e < 0: return error(bad)
				vals.append(e)
				i += 2
				continue
			if c == 34:
				if i != n - 1: return error(bad)
				closed = true
				break
			vals.append(c)
			i += 1
		if not closed: return error(bad)
		if word == ".asciz": vals.append(0)
		self.check_size(vals.length())?
		for v in vals:
			self.data.append(v)
		return ok(unit)
	return error(self.fail("unknown directive '{word}'"))

fn label_len(s: String) Int:
	b := bl(s)
	n := b.length()
	if n == 0 or not is_ident_start(b.get(0, 0)): return 0
	var i = 1
	while i < n and is_ident_char(b.get(i, 0)): i += 1
	if i < n and b.get(i, 0) == 58: return i + 1
	return 0

fn var Asm.pass1(lines: List[String], table: Map[String, Int]) Unit!:
	for li in 0..lines.length():
		self.cur = li + 1
		var rest = strip_comment(lines.get(li, "")).trim()
		while true:
			ll := label_len(rest)
			if ll == 0: break
			name := sub(rest, 0, ll - 1)
			if self.section == 0:
				self.define(name.clone(), true, self.insts.length(), "")?
				if name == "main": self.main_idx = self.insts.length()
			else:
				self.define(name.clone(), true, self.data.length(), "")?
			rest = sub(rest, ll, rest.length()).trim()
		if rest.length() == 0: continue
		b := bl(rest)
		var wend = 0
		while wend < b.length() and not (b.get(wend, 0) == 32 or b.get(wend, 0) == 9 or b.get(wend, 0) == 13 or b.get(wend, 0) == 11 or b.get(wend, 0) == 12): wend += 1
		word := sub(rest, 0, wend)
		after := sub(rest, wend, rest.length()).trim()
		if word.starts_with("."):
			self.directive(word, after)?
			continue
		if self.section == 1: return error(self.fail("instruction in data section"))
		op := table.get_or(word, -1)
		if op < 0: return error(self.fail("unknown mnemonic '{word}'"))
		var ops = List[Opd]()
		for txt in split_ops(after):
			o := self.parse_opd(txt)?
			ops.append(o)
		if ops.length() != expected_count(op): return error(self.fail("wrong number of operands for '{word}'"))
		if not classes_ok(op, ops): return error(self.fail("invalid operands for '{word}'"))
		self.items.append(Item(0, self.cur, self.insts.length(), 0, List[String]()))
		self.insts.append(PInst(op, self.cur, ops))

fn var Asm.pass2() Unit!:
	n := self.insts.length()
	for k in 0..self.items.length():
		it := self.items.get(k).clone()
		self.cur = it.line
		if it.kind == 1:
			for j in 0..it.texts.length():
				v := self.eval_expr(it.texts.get(j, ""), false)?
				self.data.set(it.idx + j, v)
		else if it.kind == 2:
			v := self.eval_expr(it.texts.get(0, ""), false)?
			for j in 0..it.count:
				self.data.set(it.idx + j, v)
		else:
			pi := self.insts.get(it.idx).clone()
			var vals = List[Int]()
			var kinds = List[Int]()
			var regs = List[Int]()
			for o in pi.ops:
				kinds.append(o.kind)
				regs.append(o.reg)
				if o.kind == 0:
					vals.append(0)
				else if o.kind == 1:
					vals.append(self.eval_expr(o.text, false)?)
				else:
					vals.append(self.eval_expr(o.text, true)?)
			if pi.op >= 20 and pi.op <= 27:
				t := vals.get(0, 0)
				if t < 0 or t >= n: return error(self.fail("invalid jump target"))
			self.code.append(Inst(pi.op, pi.line, kinds.get(0, -1), regs.get(0, -1), vals.get(0, 0), kinds.get(1, -1), regs.get(1, -1), vals.get(1, 0)))

type VM:
	regs: List[Int]
	mem: List[Int]
	code: List[Inst]
	input: List[Int]
	chars: List[String]
	pieces: List[String] = List[String]()
	inp: Int = 0
	pc: Int = 0
	steps: Int = 0
	budget: Int = 0
	z: Bool = false
	l: Bool = false
	trapped: Bool = false
	trap: String = ""
	halted: Bool = false

fn var VM.do_trap(msg: String) Unit:
	self.trapped = true
	self.trap = msg

fn var VM.rd(k: Int, r: Int, v: Int) Int:
	if k == 0: return self.regs.get(r, 0)
	if k == 1: return v
	a := if r >= 0: wrap(self.regs.get(r, 0) + v) else: v
	if a < 0 or a >= 4096:
		self.do_trap("memory access out of range: {a}")
		return 0
	return self.mem.get(a, 0)

fn var VM.wr(k: Int, r: Int, v: Int, value: Int) Unit:
	if k == 0:
		self.regs.set(r, value)
		return
	a := if r >= 0: wrap(self.regs.get(r, 0) + v) else: v
	if a < 0 or a >= 4096:
		self.do_trap("memory access out of range: {a}")
		return
	self.mem.set(a, value)

fn var VM.push(value: Int) Unit:
	sp := self.regs.get(8, 0)
	if sp <= 0:
		self.do_trap("stack overflow")
		return
	self.regs.set(8, sp - 1)
	if sp - 1 >= 4096:
		self.do_trap("memory access out of range: {sp - 1}")
		return
	self.mem.set(sp - 1, value)

fn var VM.pop() Int:
	sp := self.regs.get(8, 0)
	if sp >= 4096:
		self.do_trap("stack underflow")
		return 0
	if sp < 0:
		self.do_trap("memory access out of range: {sp}")
		return 0
	v := self.mem.get(sp, 0)
	self.regs.set(8, sp + 1)
	return v

fn alu(op: Int, x: Int, y: Int) Int:
	if op == 1: return wrap(x + y)
	if op == 2: return wrap(x - y)
	if op == 3: return wrap(x * y)
	if op == 4: return wrap(x / y)
	if op == 5: return wrap(x % y)
	if op == 6: return bit_and(x, y)
	if op == 7: return bit_or(x, y)
	if op == 8: return bit_xor(x, y)
	c := bit_and(y, 31)
	if op == 9: return wrap(shift_left(x, c))
	if op == 10: return wrap(shift_right_unsigned(bit_and(x, 4294967295), c))
	return shift_right(x, c)

fn var VM.run() Unit:
	n := self.code.length()
	while true:
		if self.steps == self.budget:
			self.do_trap("budget exceeded")
			return
		pc := self.pc
		if pc < 0 or pc >= n:
			self.do_trap("pc out of range")
			return
		ins := self.code.get(pc)
		op := ins.op
		ak := ins.ak
		ar := ins.ar
		av := ins.av
		bk := ins.bk
		br := ins.br
		bv := ins.bv
		var next = pc + 1
		if op == 0:
			v := self.rd(bk, br, bv)
			if self.trapped: return
			self.wr(ak, ar, av, v)
			if self.trapped: return
		else if op <= 12:
			y := self.rd(bk, br, bv)
			if self.trapped: return
			x := self.regs.get(ar, 0)
			if op == 12:
				self.z = x == y
				self.l = x < y
			else:
				if (op == 4 or op == 5) and y == 0:
					self.do_trap("division by zero")
					return
				self.regs.set(ar, alu(op, x, y))
		else if op == 13:
			self.regs.set(ar, wrap(0 - self.regs.get(ar, 0)))
		else if op == 14:
			self.regs.set(ar, bit_not(self.regs.get(ar, 0)))
		else if op == 15:
			self.regs.set(ar, wrap(self.regs.get(ar, 0) + 1))
		else if op == 16:
			self.regs.set(ar, wrap(self.regs.get(ar, 0) - 1))
		else if op == 17:
			a := if br >= 0: wrap(self.regs.get(br, 0) + bv) else: bv
			self.regs.set(ar, a)
		else if op == 18:
			v := self.rd(ak, ar, av)
			if self.trapped: return
			self.push(v)
			if self.trapped: return
		else if op == 19:
			v := self.pop()
			if self.trapped: return
			self.regs.set(ar, v)
		else if op >= 20 and op <= 26:
			var take = false
			if op == 20: take = true
			if op == 21: take = self.z
			if op == 22: take = not self.z
			if op == 23: take = self.l
			if op == 24: take = self.l or self.z
			if op == 25: take = not self.l and not self.z
			if op == 26: take = not self.l
			if take: next = av
		else if op == 27:
			self.push(pc + 1)
			if self.trapped: return
			next = av
		else if op == 28:
			v := self.pop()
			if self.trapped: return
			next = v
		else if op == 29:
			if self.inp >= self.input.length():
				self.do_trap("input exhausted")
				return
			self.regs.set(ar, self.input.get(self.inp, 0))
			self.inp += 1
		else if op == 30:
			v := self.rd(ak, ar, av)
			if self.trapped: return
			self.pieces.append("{v}\n")
		else if op == 31:
			v := self.rd(ak, ar, av)
			if self.trapped: return
			if v < 0 or v > 127:
				self.do_trap("invalid character")
				return
			self.pieces.append(self.chars.get(v, ""))
		else if op == 32:
			self.steps += 1
			self.halted = true
			return
		self.steps += 1
		self.pc = next

fn parse_input(lines: List[String]) List[Int]:
	var out = List[Int]()
	for tok in lines.join(" ").fields():
		b := bl(tok)
		var i = 0
		var neg = false
		if b.length() > 0 and b.get(0, 0) == 45:
			neg = true
			i = 1
		if i >= b.length(): continue
		var good = true
		var acc = 0
		while i < b.length():
			c := b.get(i, 0)
			if not is_digit(c):
				good = false
				break
			acc = bit_and(acc * 10 + (c - 48), 4294967295)
			i += 1
		if good:
			out.append(wrap(if neg: 0 - acc else: acc))
	return out

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var inp = stdin()
	raw := read_all(inp, none)?
	text := raw.decode_utf8().get("")
	all := text.lines()
	var src = List[String]()
	var rest = List[String]()
	var in_input = false
	for l in all:
		if in_input:
			rest.append(l.clone())
		else if l == "====" or l == "====\r":
			in_input = true
		else:
			src.append(l.clone())
	var asm = Asm()
	table := mnemonic_table()
	r1 := asm.pass1(src, table)
	if r1.is_error():
		print(r1.err().message)
		return ok(unit)
	r2 := asm.pass2()
	if r2.is_error():
		print(r2.err().message)
		return ok(unit)
	var regs = List[Int]()
	for _i in 0..10:
		regs.append(0)
	regs.set(8, 4096)
	var mem = List[Int]()
	for i in 0..4096:
		mem.append(asm.data.get(i, 0))
	var chars = List[String]()
	for i in 0..128:
		chars.append(from_scalars([i])?)
	start := if asm.main_idx >= 0: asm.main_idx else: 0
	var vm = VM(regs, mem, asm.code.clone(), parse_input(rest), chars)
	vm.pc = start
	vm.budget = asm.budget
	vm.run()
	out := vm.pieces.join("")
	print(out, end: "")
	if out.length() > 0 and not out.ends_with("\n"): print("")
	if vm.halted:
		print("-- halted after {vm.steps} steps")
	else:
		var line = "-"
		if vm.pc >= 0 and vm.pc < vm.code.length() and vm.trap != "pc out of range":
			line = "{vm.code.get(vm.pc).line}"
		print("-- trap: {vm.trap} (pc={vm.pc} line={line}) after {vm.steps} steps")
	print("regs: r0={vm.regs.get(0, 0)} r1={vm.regs.get(1, 0)} r2={vm.regs.get(2, 0)} r3={vm.regs.get(3, 0)} r4={vm.regs.get(4, 0)} r5={vm.regs.get(5, 0)} r6={vm.regs.get(6, 0)} r7={vm.regs.get(7, 0)} sp={vm.regs.get(8, 0)} bp={vm.regs.get(9, 0)}")
	zf := if vm.z: 1 else: 0
	lf := if vm.l: 1 else: 0
	print("flags: Z={zf} L={lf}")
