import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
	bit_and, bit_not, bit_or, bit_xor from "@std/math/math.ms",
	from_scalars from "@std/string.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn wrap(x: Int) Int:
	m := ((x % 4294967296) + 4294967296) % 4294967296
	if m >= 2147483648: return m - 4294967296

	return m

fn cat(s: String, i: Int) Int:
	if i < 0 or i >= s.length(): return -1
	return s.scalar_at(i, default: -1)

fn sub(s: String, a: Int, b: Int) String:
	if b <= a: return ""
	return s.view(a, b).clone()

fn is_digit(c: Int) Bool: c >= 48 and c <= 57

fn is_ident_start(c: Int) Bool: (
	(c >= 65 and c <= 90)
	or (c >= 97 and c <= 122)
	or c == 95
)

fn is_word(c: Int) Bool: is_ident_start(c) or is_digit(c) or c == 46

fn is_ws(c: Int) Bool: c == 32 or c == 9 or c == 13

fn is_ident(t: String) Bool:
	if t.length() == 0: return false
	if not is_ident_start(cat(t, 0)): return false

	for i in 1..t.length():
		if not (is_ident_start(cat(t, i)) or is_digit(cat(t, i))): return false
	return true

fn reg_index(t: String) Int:
	if t == "sp": return 8
	if t == "bp": return 9

	if t.length() == 2 and cat(t, 0) == 114:
		d := cat(t, 1) - 48
		if d >= 0 and d <= 7: return d

	return -1

fn char_lit_len(s: String, i: Int) Int:
	c1 := cat(s, i + 1)
	if c1 == 92 and cat(s, i + 3) == 39: return 4
	if c1 != -1 and c1 != 92 and c1 != 39 and cat(s, i + 2) == 39: return 3

	return 1

fn strip_comment(s: String) String:
	n := s.length()
	var i = 0

	while i < n:
		c := cat(s, i)
		if c == 59: return sub(s, 0, i)

		if c == 34:
			i += 1

			while i < n:
				d := cat(s, i)

				if d == 92:
					i += 2
					continue

				if d == 34: break

				i += 1

			i += 1
			continue

		if c == 39:
			i += char_lit_len(s, i)
			continue

		i += 1

	return s.clone()

fn split_ops(args: String) List[String]:
	var out = List[String]()
	if args == "": return out

	n := args.length()
	var depth = 0
	var start = 0
	var i = 0

	while i < n:
		c := cat(args, i)

		if c == 39:
			i += char_lit_len(args, i)
			continue

		if c == 91: depth += 1
		if c == 93 and depth > 0: depth -= 1

		if c == 44 and depth == 0:
			out.append(sub(args, start, i).trim())
			start = i + 1

		i += 1

	out.append(sub(args, start, n).trim())
	return out

type Term:
	neg: Bool
	text: String

type Opnd:
	kind: Int
	reg: Int
	text: String
	terms: List[Term]

type Instr:
	op: Int
	line: Int
	a: Opnd
	b: Opnd

type Stmt:
	kind: Int
	line: Int
	idx: Int
	texts: List[String]

type Sym:
	is_equ: Bool
	text_sec: Bool
	value: Int
	text: String
	state: Int

fn bad_op(t: String) Error: Error(f"invalid operand '{t}'")

fn split_terms(inner: String) List[Term]:
	var out = List[Term]()
	n := inner.length()
	var start = 0
	var neg = false
	var i = 0

	while i < n:
		c := cat(inner, i)

		if c == 39:
			i += char_lit_len(inner, i)
			continue

		if c == 43 or c == 45:
			out.append(Term(neg: neg, text: sub(inner, start, i).trim()))
			neg = c == 45
			start = i + 1

		i += 1

	out.append(Term(neg: neg, text: sub(inner, start, n).trim()))
	return out

fn parse_operand(t: String) Opnd!:
	if t == "": return error(bad_op(t))

	r := reg_index(t)
	if r >= 0: return ok(Opnd(kind: 0, reg: r, text: "", terms: List[Term]()))

	if cat(t, 0) == 91:
		n := t.length()
		if n < 2 or cat(t, n - 1) != 93: return error(bad_op(t))

		inner := sub(t, 1, n - 1).trim()
		if inner == "": return error(bad_op(t))

		parts := split_terms(inner)
		var terms = List[Term]()
		var reg = -1

		for k in 0..parts.length():
			p := parts[k]
			if k == 0 and p.text == "" and parts.length() > 1: continue
			if p.text == "": return error(bad_op(t))

			ri := reg_index(p.text)

			if ri >= 0:
				if p.neg or reg >= 0: return error(bad_op(t))

				reg = ri
			else:
				terms.append(Term(neg: p.neg, text: p.text.clone()))

		return ok(Opnd(kind: 2, reg: reg, text: inner, terms: terms))

	return ok(Opnd(kind: 1, reg: -1, text: t.clone(), terms: List[Term]()))

fn mnemonic(name: String) Int:
	names := [
		"mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr",
		"sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je",
		"jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt",
		"nop"
	]
	for i in 0..names.length():
		if names[i] == name: return i
	if name == "jz": return 21
	if name == "jnz": return 22

	return -1

fn expected_count(op: Int) Int:
	if op == 0 or (op >= 1 and op <= 12) or op == 17: return 2
	if op == 28 or op == 32 or op == 33: return 0

	return 1

fn classes_ok(op: Int, a: Opnd, b: Opnd) Bool:
	if op == 0:
		if a.kind == 0: return true
		if a.kind == 2: return b.kind != 2

		return false

	if op >= 1 and op <= 12: return a.kind == 0
	if op == 17: return a.kind == 0 and b.kind == 2
	if op == 13 or op == 14 or op == 15 or op == 16 or op == 19 or op == 29: return (
		a.kind == 0
	)
	if op == 18 or op == 30 or op == 31: return true
	if op >= 20 and op <= 27: return a.kind == 1

	return true

fn parse_digits(t: String) Int:
	if t == "": return -1

	var v = 0

	for i in 0..t.length():
		d := cat(t, i)
		if not is_digit(d): return -1

		v = v * 10 + (d - 48)
		if v > 100000000000: v = 100000000000

	return v

type Asm:
	syms: Map[String, Sym] = Map[String, Sym]()
	instrs: List[Instr] = List[Instr]()
	stmts: List[Stmt] = List[Stmt]()
	data: List[Int] = List[Int]()
	in_data: Bool = false
	budget: Int = 100000
	cur_line: Int = 0

fn var Asm.define(name: String, sym: Sym) Void!:
	if reg_index(name) >= 0: return error(Error(f"reserved name '{name}'"))
	if self.syms.get(name) != null: return error(Error(f"duplicate symbol '{name}'"))

	self.syms[name.clone()] = sym

fn inval(disp: String) Error: Error(f"invalid expression '{disp}'")

fn var Asm.sym_value(name: String) Int!:
	var found = false
	var is_equ = false
	var state = 0
	var value = 0
	var text = ""

	if s := self.syms.get(name):
		found = true
		is_equ = s.is_equ
		state = s.state
		value = s.value
		text = s.text.clone()

	if not found: return error(Error(f"undefined symbol '{name}'"))
	if not is_equ: return ok(value)
	if state == 2: return ok(value)
	if state == 1: return error(Error(f"circular definition of '{name}'"))

	self.syms[name.clone()] = Sym(
		is_equ: true,
		text_sec: false,
		value: 0,
		text: text.clone(),
		state: 1,
	)

	v := self.eval(text, text)?
	self.syms[name.clone()] = Sym(
		is_equ: true,
		text_sec: false,
		value: v,
		text: text.clone(),
		state: 2,
	)
	return ok(v)

fn var Asm.word_value(word: String, disp: String) Int!:
	c := cat(word, 0)

	if is_digit(c):
		n := word.length()
		var base = 10
		var start = 0

		if c == 48 and n >= 2 and cat(word, 1) == 120:
			base = 16
			start = 2

		if c == 48 and n >= 2 and cat(word, 1) == 98:
			base = 2
			start = 2

		if start == 2 and n == 2: return error(inval(disp))

		var v = 0

		for i in start..n:
			d := cat(word, i)
			var dv = -1
			if is_digit(d): dv = d - 48
			if d >= 97 and d <= 102: dv = d - 87
			if d >= 65 and d <= 70: dv = d - 55
			if dv < 0 or dv >= base: return error(inval(disp))

			v = v * base + dv
			if v > 4294967296: v = 4294967296

		if v > 4294967295: return error(Error("immediate out of range"))

		return ok(wrap(v))

	if is_ident_start(c): return self.sym_value(word)

	return error(inval(disp))

fn var Asm.eval(text0: String, disp: String) Int!:
	text := text0.trim()
	n := text.length()
	var i = 0
	var sign = 1
	var acc = 0

	if n > 0 and (cat(text, 0) == 43 or cat(text, 0) == 45):
		if cat(text, 0) == 45: sign = -1
		i = 1

	while true:
		while is_ws(cat(text, i)):
			i += 1

		c := cat(text, i)
		var val = 0

		if c == 39:
			c1 := cat(text, i + 1)

			if c1 == 92:
				e := cat(text, i + 2)
				if cat(text, i + 3) != 39: return error(inval(disp))

				if e == 110: val = 10
				else if e == 116: val = 9
				else if e == 48: val = 0
				else if e == 92 or e == 39 or e == 34: val = e
				else: return error(inval(disp))

				i += 4
			else:
				if c1 == -1 or c1 == 39 or cat(text, i + 2) != 39: return error(
					inval(disp)
				)

				val = c1
				i += 3
		else:
			var j = i
			while is_word(cat(text, j)):
				j += 1
			if j == i: return error(inval(disp))

			val = self.word_value(sub(text, i, j), disp)?
			i = j

		acc = wrap(acc + sign * val)
		while is_ws(cat(text, i)):
			i += 1
		if i >= n: break

		c2 := cat(text, i)

		if c2 == 43: sign = 1
		else if c2 == 45: sign = -1
		else: return error(inval(disp))

		i += 1

	return ok(acc)

fn var Asm.eval_mem(o: Opnd) Int!:
	var sum = 0

	for t in o.terms:
		v := self.eval(t.text, o.text)?

		if t.neg: sum = wrap(sum - v)
		else: sum = wrap(sum + v)

	return ok(sum)

fn parse_string(t: String) List[Int]!:
	n := t.length()
	if n < 2 or cat(t, 0) != 34 or cat(t, n - 1) != 34: return error(
		Error("invalid string")
	)

	var out = List[Int]()
	bytes := sub(t, 1, n - 1).to_bytes().values()
	var i = 0

	while i < bytes.length():
		b := bytes[i].to_int()
		if b == 34: return error(Error("invalid string"))

		if b == 92:
			if i + 1 >= bytes.length(): return error(Error("invalid string"))

			e := bytes[i + 1].to_int()

			if e == 110: out.append(10)
			else if e == 116: out.append(9)
			else if e == 48: out.append(0)
			else if e == 92 or e == 39 or e == 34: out.append(e)
			else: return error(Error("invalid string"))

			i += 2
		else:
			out.append(b)
			i += 1

	return ok(out)

fn var Asm.add_data(count: Int, value: Int) Void!:
	if self.data.length() + count > 4096: return error(Error("data section too large"))

	for _k in 0..count:
		self.data.append(value)
	return ok()

fn var Asm.directive(line: Int, word: String, args: String) Void!:
	if word == ".text" or word == ".data":
		if args != "": return error(bad_op(args))

		self.in_data = word == ".data"
		return ok()

	if word == ".budget":
		v := parse_digits(args)
		if v < 1 or v > 10000000: return error(bad_op(args))

		self.budget = v
		return ok()

	if word == ".equ":
		parts := split_ops(args)
		if parts.length() != 2: return error(
			Error("wrong number of operands for '.equ'")
		)

		name := parts[0].clone()
		if not is_ident(name): return error(bad_op(name))

		self.define(
			name,
			Sym(
				is_equ: true,
				text_sec: false,
				value: 0,
				text: parts[1].clone(),
				state: 0,
			),
		)?
		return ok()

	if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
		if not self.in_data: return error(Error("data directive in text section"))

		if word == ".word":
			parts := split_ops(args)
			if parts.length() < 1: return error(
				Error("wrong number of operands for '.word'")
			)

			idx := self.data.length()
			self.add_data(parts.length(), 0)?
			self.stmts.append(Stmt(kind: 1, line: line, idx: idx, texts: parts))
			return ok()

		if word == ".space":
			parts := split_ops(args)
			if parts.length() < 1 or parts.length() > 2: return error(
				Error("wrong number of operands for '.space'")
			)

			n := self.eval(parts[0], parts[0])?
			if n < 0: return error(bad_op(parts[0]))

			idx := self.data.length()
			self.add_data(n, 0)?
			if parts.length() == 2:
				self.stmts.append(
					Stmt(
						kind: 2,
						line: line,
						idx: idx,
						texts: [parts[1].clone(), f"{n}"],
					)
				)
			return ok()

		vals := parse_string(args)?
		for v in vals:
			self.data.append(v)
		if word == ".asciz": self.data.append(0)
		if self.data.length() > 4096: return error(Error("data section too large"))

		return ok()

	return error(Error(f"unknown directive '{word}'"))

fn var Asm.line(line: Int, raw: String) Void!:
	s := strip_comment(raw)
	n := s.length()
	var pos = 0

	while true:
		while is_ws(cat(s, pos)):
			pos += 1

		var j = pos

		if is_ident_start(cat(s, j)):
			while is_word(cat(s, j)):
				j += 1

			if cat(s, j) == 58:
				name := sub(s, pos, j)
				var sym = Sym(
					is_equ: false,
					text_sec: not self.in_data,
					value: self.data.length(),
					text: "",
					state: 2,
				)
				if not self.in_data: sym = Sym(
					is_equ: false,
					text_sec: true,
					value: self.instrs.length(),
					text: "",
					state: 2,
				)
				self.define(name, sym)?
				pos = j + 1
				continue

		break

	rest := sub(s, pos, n).trim()
	if rest == "": return ok()

	var we = 0
	while we < rest.length() and not is_ws(cat(rest, we)):
		we += 1

	word := sub(rest, 0, we)
	args := sub(rest, we, rest.length()).trim()
	if cat(word, 0) == 46: return self.directive(line, word, args)
	if self.in_data: return error(Error("instruction in data section"))

	op := mnemonic(word)
	if op < 0: return error(Error(f"unknown mnemonic '{word}'"))

	texts := split_ops(args)
	var ops = List[Opnd]()
	for t in texts:
		ops.append(parse_operand(t)?)
	if ops.length() != expected_count(op): return error(
		Error(f"wrong number of operands for '{word}'")
	)

	empty := Opnd(kind: -1, reg: -1, text: "", terms: List[Term]())
	a := if ops.length() > 0: ops[0].clone() else: empty.clone()
	b := if ops.length() > 1: ops[1].clone() else: empty.clone()
	if not classes_ok(op, a, b): return error(Error(f"invalid operands for '{word}'"))

	self.stmts.append(
		Stmt(
			kind: 0,
			line: line,
			idx: self.instrs.length(),
			texts: List[String](),
		)
	)
	self.instrs.append(Instr(op: op, line: line, a: a, b: b))
	return ok()

fn var Asm.pass2(var av: List[Int], var bv: List[Int]) Void!:
	for st in self.stmts.clone():
		self.cur_line = st.line

		if st.kind == 1:
			for k in 0..st.texts.length():
				v := self.eval(st.texts[k], st.texts[k])?
				self.data[st.idx + k] = v
		else if st.kind == 2:
			v := self.eval(st.texts[0], st.texts[0])?
			cnt := parse_digits(st.texts[1])
			for k in 0..cnt:
				self.data[st.idx + k] = v
		else:
			ins := self.instrs[st.idx].clone()

			if ins.a.kind == 1: av[st.idx] = self.eval(ins.a.text, ins.a.text)?
			else if ins.a.kind == 2: av[st.idx] = self.eval_mem(ins.a)?

			if ins.b.kind == 1: bv[st.idx] = self.eval(ins.b.text, ins.b.text)?
			else if ins.b.kind == 2: bv[st.idx] = self.eval_mem(ins.b)?

			if ins.op >= 20 and ins.op <= 27:
				t := av[st.idx]
				if t < 0 or t >= self.instrs.length(): return error(
					Error("invalid jump target")
				)

	return ok()

type Vm:
	op: List[Int]
	ak: List[Int]
	ar: List[Int]
	av: List[Int]
	bk: List[Int]
	br: List[Int]
	bv: List[Int]
	regs: List[Int]
	mem: List[Int]
	input: List[Int]
	pow2: List[Int]
	out: StringBuilder
	chars: List[String]
	in_pos: Int = 0
	pc: Int = 0
	trap: String = ""
	halted: Bool = false
	zf: Bool = false
	lf: Bool = false
	last: Int = 10
	wrote: Bool = false

fn var Vm.fail(msg: String) Void:
	if self.trap == "": self.trap = msg

fn var Vm.eff(r: Int, v: Int) Int:
	base := if r >= 0: self.regs[r] else: 0
	return wrap(base + v)

fn var Vm.load(addr: Int) Int:
	if addr < 0 or addr >= 4096:
		self.fail(f"memory access out of range: {addr}")
		return 0

	return self.mem[addr]

fn var Vm.store(addr: Int, v: Int) Void:
	if addr < 0 or addr >= 4096:
		self.fail(f"memory access out of range: {addr}")
		return

	self.mem[addr] = v

fn var Vm.rd(k: Int, r: Int, v: Int) Int:
	if k == 0: return self.regs[r]
	if k == 1: return v

	return self.load(self.eff(r, v))

fn var Vm.push(v: Int) Void:
	if self.regs[8] <= 0:
		self.fail("stack overflow")
		return

	self.regs[8] -= 1
	self.store(self.regs[8], v)

fn var Vm.pop() Int:
	if self.regs[8] >= 4096:
		self.fail("stack underflow")
		return 0

	v := self.load(self.regs[8])
	if self.trap != "": return 0

	self.regs[8] += 1
	return v

fn var Vm.emit(s: String, lastc: Int) Void:
	self.out.append(s)
	self.last = lastc
	self.wrote = true

fn tdiv(d: Int, s: Int) Int:
	q := d.abs() / s.abs()
	if (d < 0) != (s < 0): return -q

	return q

fn var Vm.alu(op: Int, d: Int, s: Int) Int:
	if op == 1: return wrap(d + s)
	if op == 2: return wrap(d - s)
	if op == 3: return wrap(d * s)

	if op == 4 or op == 5:
		if s == 0:
			self.fail("division by zero")
			return 0

		q := tdiv(d, s)
		if op == 4: return wrap(q)

		return wrap(d - q * s)

	if op == 6: return bit_and(d, s)
	if op == 7: return bit_or(d, s)
	if op == 8: return bit_xor(d, s)

	c := bit_and(s, 31)
	p := self.pow2[c]
	if op == 9: return wrap(d * p)

	if op == 10:
		u := if d < 0: d + 4294967296 else: d
		return wrap(u / p)

	if d >= 0: return d / p

	return bit_not(bit_not(d) / p)

fn var Vm.step() Void:
	pc := self.pc
	op := self.op[pc]
	ak := self.ak[pc]
	ar := self.ar[pc]
	av := self.av[pc]
	bk := self.bk[pc]
	br := self.br[pc]
	bv := self.bv[pc]
	var next = pc + 1

	if op == 0:
		s := self.rd(bk, br, bv)
		if self.trap != "": return

		if ak == 0: self.regs[ar] = s
		else: self.store(self.eff(ar, av), s)
	else if op >= 1 and op <= 12:
		s := self.rd(bk, br, bv)
		if self.trap != "": return

		d := self.regs[ar]

		if op == 12:
			self.zf = d == s
			self.lf = d < s
		else:
			r := self.alu(op, d, s)
			if self.trap != "": return

			self.regs[ar] = r
	else if op == 13: self.regs[ar] = wrap(-self.regs[ar])
	else if op == 14: self.regs[ar] = bit_not(self.regs[ar])
	else if op == 15: self.regs[ar] = wrap(self.regs[ar] + 1)
	else if op == 16: self.regs[ar] = wrap(self.regs[ar] - 1)
	else if op == 17:
		ea := self.eff(br, bv)
		self.regs[ar] = ea
	else if op == 18:
		v := self.rd(ak, ar, av)
		if self.trap != "": return

		self.push(v)
	else if op == 19:
		v := self.pop()
		if self.trap != "": return

		self.regs[ar] = v
	else if op >= 20 and op <= 26:
		var take = false

		if op == 20: take = true
		else if op == 21: take = self.zf
		else if op == 22: take = not self.zf
		else if op == 23: take = self.lf
		else if op == 24: take = self.lf or self.zf
		else if op == 25: take = not self.lf and not self.zf
		else: take = not self.lf

		if take: next = av
	else if op == 27:
		self.push(pc + 1)
		if self.trap != "": return

		next = av
	else if op == 28:
		v := self.pop()
		if self.trap != "": return

		next = v
	else if op == 29:
		if self.in_pos >= self.input.length():
			self.fail("input exhausted")
			return

		self.regs[ar] = self.input[self.in_pos]
		self.in_pos += 1
	else if op == 30:
		v := self.rd(ak, ar, av)
		if self.trap != "": return

		self.emit(f"{v}\n", 10)
	else if op == 31:
		v := self.rd(ak, ar, av)
		if self.trap != "": return

		if v < 0 or v > 127:
			self.fail("invalid character")
			return

		self.emit(self.chars[v].clone(), v)
	else if op == 32: self.halted = true

	self.pc = next

fn parse_input(lines: List[String]) List[Int]:
	var out = List[Int]()

	for ln in lines:
		for tok in ln.fields():
			neg := cat(tok, 0) == 45
			digits := if neg: sub(tok, 1, tok.length()) else: tok.clone()
			if digits == "": continue

			var ok_tok = true
			var v = 0

			for i in 0..digits.length():
				d := cat(digits, i)

				if not is_digit(d):
					ok_tok = false
					break

				v = (v * 10 + (d - 48)) % 4294967296

			if not ok_tok: continue

			out.append(if neg: wrap(-v) else: wrap(v))

	return out

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Void!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8() or ""
	all := text.lines()
	var src = List[String]()
	var inp_lines = List[String]()
	var seen = false

	for ln in all:
		if seen:
			inp_lines.append(ln.clone())
		else if ln == "====":
			seen = true
		else:
			src.append(ln.clone())

	var asm = Asm()
	var err = ""
	var errline = 0

	for k in 0..src.length():
		r := asm.line(k + 1, src[k])

		if _u := r:
			continue
		else:
			err = r.err().message
			errline = k + 1
			break

	n := asm.instrs.length()
	var av = List[Int]()
	var bv = List[Int]()

	for _k in 0..n:
		av.append(0)
		bv.append(0)

	if err == "":
		r := asm.pass2(av, bv)

		if _u := r:
			err = ""
		else:
			err = r.err().message
			errline = asm.cur_line

	if err != "":
		print(f"asm error line {errline}: {err}")
		return

	var op = List[Int]()
	var ak = List[Int]()
	var ar = List[Int]()
	var bk = List[Int]()
	var br = List[Int]()
	var lines_of = List[Int]()

	for ins in asm.instrs:
		op.append(ins.op)
		ak.append(ins.a.kind)
		ar.append(ins.a.reg)
		bk.append(ins.b.kind)
		br.append(ins.b.reg)
		lines_of.append(ins.line)

	var mem = List[Int]()
	for k in 0..4096:
		mem.append(if k < asm.data.length(): asm.data[k] else: 0)

	var regs = List[Int]()
	for _k in 0..10:
		regs.append(0)
	regs[8] = 4096

	var pow2 = List[Int]()
	var p = 1

	for _k in 0..32:
		pow2.append(p)
		p *= 2

	var chars = List[String]()
	for k in 0..128:
		chars.append(from_scalars([k])?)

	var start = 0
	if m := asm.syms.get("main"):
		if m.text_sec and not m.is_equ: start = m.value

	var vm = Vm(
		op: op,
		ak: ak,
		ar: ar,
		av: av,
		bk: bk,
		br: br,
		bv: bv,
		regs: regs,
		mem: mem,
		input: parse_input(inp_lines),
		pow2: pow2,
		out: StringBuilder(),
		chars: chars,
	)
	vm.pc = start

	var steps = 0
	var trap = ""
	var trap_pc = 0
	let_budget := asm.budget

	while true:
		pc := vm.pc

		if pc < 0 or pc >= n:
			trap = "pc out of range"
			trap_pc = pc
			break

		if steps == let_budget:
			trap = "budget exceeded"
			trap_pc = pc
			break

		vm.step()

		if vm.trap != "":
			trap = vm.trap.clone()
			trap_pc = pc
			break

		steps += 1
		if vm.halted: break

	output := vm.out.build()
	print(output, end: "")
	if vm.wrote and vm.last != 10: print("")

	if trap == "":
		print(f"-- halted after {steps} steps")
	else:
		ln := if trap == "pc out of range": "-" else: f"{lines_of[trap_pc]}"
		print(f"-- trap: {trap} (pc={trap_pc} line={ln}) after {steps} steps")

	r := vm.regs
	print(
		f"regs: r0={r[0]} r1={r[1]} r2={r[2]} r3={r[3]} r4={r[4]} r5={r[5]} r6={r[6]} r7={r[7]} sp={r[8]} bp={r[9]}"
	)

	zf := if vm.zf: 1 else: 0
	lf := if vm.lf: 1 else: 0
	print(f"flags: Z={zf} L={lf}")
