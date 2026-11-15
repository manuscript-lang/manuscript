import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import bit_and, bit_or, bit_xor, bit_not, shift_left, shift_right, shift_right_unsigned from "@std/math/math.ms"
import from_scalars from "@std/string.ms"

type Opnd:
	kind: Int
	reg: Int
	text: String

type Instr:
	op: Int
	name: String
	line: Int
	ops: List[Opnd]

type DItem:
	line: Int
	kind: Int
	exprs: List[String]
	bytes: List[Int]
	count: Int
	addr: Int

type Item:
	line: Int
	is_instr: Bool
	idx: Int

type Terms:
	signs: List[Int]
	terms: List[String]

type Ctx:
	labels: Map[String, Int] = Map[String, Int]()
	equs: Map[String, String] = Map[String, String]()
	equ_val: Map[String, Int] = Map[String, Int]()
	evaluating: Set[String] = Set[String]()
	instrs: List[Instr] = List[Instr]()
	ditems: List[DItem] = List[DItem]()
	items: List[Item] = List[Item]()
	in_data: Bool = false
	dsize: Int = 0
	budget: Int = 100000
	main_pc: Int = -1
	cur_line: Int = 0
	mem: List[Int] = List[Int]()
	p_op: List[Int] = List[Int]()
	p_ln: List[Int] = List[Int]()
	p_ak: List[Int] = List[Int]()
	p_ar: List[Int] = List[Int]()
	p_av: List[Int] = List[Int]()
	p_bk: List[Int] = List[Int]()
	p_br: List[Int] = List[Int]()
	p_bv: List[Int] = List[Int]()

fn wrap(x: Int) Int:
	m := bit_and(x, 4294967295)
	if m >= 2147483648: return m - 4294967296
	return m

fn code(c: String) Int: c.scalar_at(0)

fn is_digit(c: String) Bool:
	k := code(c)
	return k >= 48 and k <= 57

fn is_ident_start(c: String) Bool:
	k := code(c)
	return (k >= 65 and k <= 90) or (k >= 97 and k <= 122) or k == 95

fn is_ident_char(c: String) Bool:
	return is_ident_start(c) or is_digit(c) or c == "."

fn is_ident(s: String) Bool:
	cs := s.chars()
	if cs.length() == 0: return false
	if not is_ident_start(cs[0]): return false
	for c in cs:
		if not is_ident_char(c): return false
	return true

fn sub(cs: List[String], a: Int, b: Int) String:
	var s = ""
	for i in a..b:
		s += cs[i]
	return s

fn reg_index(s: String) Int:
	if s == "sp": return 8
	if s == "bp": return 9
	if s.length() == 2 and s.starts_with("r"):
		sc := s.chars()
		k := code(sc[1])
		if k >= 48 and k <= 55: return k - 48
	return -1

fn esc_value(c: String) Int:
	if c == "n": return 10
	if c == "t": return 9
	if c == "0": return 0
	if c == "\\": return 92
	if c == "'": return 39
	if c == "\"": return 34
	return -1

// end index (exclusive) of a valid char literal starting at i, or -1
fn char_lit_end(cs: List[String], i: Int) Int:
	n := cs.length()
	if cs[i] != "'": return -1
	if i + 2 >= n: return -1
	if cs[i + 1] == "\\":
		if i + 3 >= n: return -1
		if cs[i + 3] != "'": return -1
		if esc_value(cs[i + 2]) < 0: return -1
		return i + 4
	if cs[i + 1] == "'": return -1
	if cs[i + 2] != "'": return -1
	return i + 3

fn strip_comment(line: String) String:
	cs := line.chars()
	n := cs.length()
	var i = 0
	while i < n:
		c := cs[i]
		if c == ";": return sub(cs, 0, i)
		if c == "'":
			e := char_lit_end(cs, i)
			if e > 0:
				i = e
				continue
		if c == "\"":
			i += 1
			while i < n:
				if cs[i] == "\\":
					i += 2
					continue
				if cs[i] == "\"": break
				i += 1
			i += 1
			continue
		i += 1
	return line.clone()

fn split_operands(s: String) List[String]:
	if s.trim() == "": return List[String]()
	cs := s.chars()
	n := cs.length()
	var out = List[String]()
	var start = 0
	var i = 0
	var inb = false
	while i < n:
		c := cs[i]
		if c == "'":
			e := char_lit_end(cs, i)
			if e > 0:
				i = e
				continue
		if c == "[": inb = true
		else if c == "]": inb = false
		else if c == "," and not inb:
			out.append(sub(cs, start, i).trim())
			start = i + 1
		i += 1
	out.append(sub(cs, start, n).trim())
	return out

fn split_terms(t: String) Terms:
	cs := t.chars()
	n := cs.length()
	var signs = List[Int]()
	var terms = List[String]()
	var i = 0
	var sign = 1
	if n > 0 and (cs[0] == "+" or cs[0] == "-"):
		if cs[0] == "-": sign = -1
		i = 1
	while true:
		start := i
		while i < n:
			c := cs[i]
			if c == "'":
				e := char_lit_end(cs, i)
				if e > 0:
					i = e
					continue
			if c == "+" or c == "-": break
			i += 1
		signs.append(sign)
		terms.append(sub(cs, start, i).trim())
		if i >= n: break
		sign = if cs[i] == "-": -1 else: 1
		i += 1
	return Terms(signs, terms)

fn bad(msg: String) Int!:
	return error(Error(msg))

fn parse_number(term: String, whole: String) Int!:
	cs := term.chars()
	n := cs.length()
	var radix = 10
	var start = 0
	if n > 2 and cs[0] == "0" and cs[1] == "x":
		radix = 16
		start = 2
	else if n > 2 and cs[0] == "0" and cs[1] == "b":
		radix = 2
		start = 2
	var v = 0
	var big = false
	for i in start..n:
		k := code(cs[i])
		var d = -1
		if k >= 48 and k <= 57: d = k - 48
		else if k >= 97 and k <= 102: d = k - 87
		else if k >= 65 and k <= 70: d = k - 55
		if d < 0 or d >= radix: return bad("invalid expression '{whole}'")
		if not big:
			v = v * radix + d
			if v > 4294967295: big = true
	if big: return bad("immediate out of range")
	return ok(wrap(v))

fn var Ctx.eval_term(term: String, whole: String) Int!:
	if term == "": return bad("invalid expression '{whole}'")
	cs := term.chars()
	if is_digit(cs[0]): return parse_number(term, whole)
	if cs[0] == "'":
		e := char_lit_end(cs, 0)
		if e != cs.length(): return bad("invalid expression '{whole}'")
		if cs[1] == "\\": return ok(esc_value(cs[2]))
		bs := cs[1].to_bytes().values()
		if bs.length() != 1: return bad("invalid expression '{whole}'")
		return ok(code(cs[1]))
	if not is_ident(term): return bad("invalid expression '{whole}'")
	if self.labels.contains(term): return ok(self.labels.get_or(term, 0))
	if self.equ_val.contains(term): return ok(self.equ_val.get_or(term, 0))
	if self.equs.contains(term):
		if self.evaluating.contains(term): return bad("circular definition of '{term}'")
		self.evaluating.add(term.clone())
		src := self.equs.get_or(term, "")
		v := self.eval(src)?
		self.evaluating.remove(term.clone())
		self.equ_val[term.clone()] = v
		return ok(v)
	return bad("undefined symbol '{term}'")

fn var Ctx.eval(text: String) Int!:
	t := text.trim()
	tm := split_terms(t)
	var total = 0
	for i in 0..tm.terms.length():
		v := self.eval_term(tm.terms[i].clone(), t)?
		if tm.signs[i] < 0: total = wrap(total - v)
		else: total = wrap(total + v)
	return ok(total)

fn var Ctx.eval_top(text: String) Int!:
	self.evaluating = Set[String]()
	return self.eval(text)

fn parse_string(s: String) List[Int]!:
	cs := s.chars()
	n := cs.length()
	if n < 2 or cs[0] != "\"" or cs[n - 1] != "\"": return error(Error("invalid string"))
	var out = List[Int]()
	var i = 1
	while i < n - 1:
		c := cs[i]
		if c == "\"": return error(Error("invalid string"))
		if c == "\\":
			if i + 1 >= n - 1: return error(Error("invalid string"))
			e := esc_value(cs[i + 1])
			if e < 0: return error(Error("invalid string"))
			out.append(e)
			i += 2
			continue
		for b in c.to_bytes().values():
			out.append(b.to_int())
		i += 1
	return ok(out)

fn mnemonic_op(name: String) Int:
	names := ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]
	if name == "jz": return 21
	if name == "jnz": return 22
	for i in 0..names.length():
		if names[i] == name: return i
	return -1

fn arity(op: Int) Int:
	if op <= 12 or op == 17: return 2
	if op == 28 or op >= 32: return 0
	return 1

fn classes_ok(op: Int, ops: List[Opnd]) Bool:
	if op == 0:
		if ops[0].kind == 0: return true
		if ops[0].kind == 2: return ops[1].kind != 2
		return false
	if op <= 12: return ops[0].kind == 0
	if op == 17: return ops[0].kind == 0 and ops[1].kind == 2
	if op == 13 or op == 14 or op == 15 or op == 16 or op == 19 or op == 29: return ops[0].kind == 0
	if op == 18 or op == 30 or op == 31: return true
	if op >= 20 and op <= 27: return ops[0].kind == 1
	return true

fn parse_operand(text: String) Opnd!:
	if text == "": return error(Error("invalid operand ''"))
	r := reg_index(text)
	if r >= 0: return ok(Opnd(0, r, ""))
	if text.starts_with("["):
		if not text.ends_with("]") or text.length() < 2: return error(Error("invalid operand '{text}'"))
		inner := text.slice(1, text.length() - 1)?
		tm := split_terms(inner.trim())
		var base = -1
		var rest = ""
		for i in 0..tm.terms.length():
			term := tm.terms[i]
			if term == "": return error(Error("invalid operand '{text}'"))
			ri := reg_index(term)
			if ri >= 0:
				if tm.signs[i] < 0 or base >= 0: return error(Error("invalid operand '{text}'"))
				base = ri
			else:
				rest += if tm.signs[i] < 0: "-" else: "+"
				rest += term
		return ok(Opnd(2, base, rest))
	return ok(Opnd(1, 0, text))

fn var Ctx.define_label(name: String) Unit!:
	if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
	if self.labels.contains(name) or self.equs.contains(name): return error(Error("duplicate symbol '{name}'"))
	if self.in_data:
		self.labels[name.clone()] = self.dsize
	else:
		self.labels[name.clone()] = self.instrs.length()
		if name == "main": self.main_pc = self.instrs.length()
	return ok(unit)

fn var Ctx.add_data(line: Int, kind: Int, exprs: List[String], bytes: List[Int], count: Int) Unit!:
	if self.dsize + count > 4096: return error(Error("data section too large"))
	self.ditems.append(DItem(line, kind, exprs, bytes, count, self.dsize))
	self.items.append(Item(line, false, self.ditems.length() - 1))
	self.dsize += count
	return ok(unit)

fn var Ctx.directive(line: Int, word: String, args: String) Unit!:
	if word == ".text" or word == ".data":
		if args != "": return error(Error("invalid operand '{args}'"))
		self.in_data = word == ".data"
		return ok(unit)
	if word == ".equ":
		ops := split_operands(args)
		if ops.length() != 2: return error(Error("wrong number of operands for '.equ'"))
		name := ops[0]
		if not is_ident(name): return error(Error("invalid operand '{name}'"))
		if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
		if self.labels.contains(name) or self.equs.contains(name): return error(Error("duplicate symbol '{name}'"))
		self.equs[name.clone()] = ops[1].clone()
		return ok(unit)
	if word == ".budget":
		cs := args.chars()
		var ok_num = cs.length() > 0 and cs.length() <= 9
		for c in cs:
			if not is_digit(c): ok_num = false
		if ok_num:
			v := args.parse_int().get(0)
			if v >= 1 and v <= 10000000:
				self.budget = v
				return ok(unit)
		return error(Error("invalid operand '{args}'"))
	if word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space":
		if not self.in_data: return error(Error("data directive in text section"))
		if word == ".word":
			ops := split_operands(args)
			if ops.length() < 1: return error(Error("wrong number of operands for '.word'"))
			return self.add_data(line, 0, ops.clone(), List[Int](), ops.length())
		if word == ".space":
			ops := split_operands(args)
			if ops.length() < 1 or ops.length() > 2: return error(Error("wrong number of operands for '.space'"))
			n := self.eval_top(ops[0])?
			if n < 0: return error(Error("invalid operand '{ops[0]}'"))
			fill := if ops.length() == 2: ops[1].clone() else: "0"
			return self.add_data(line, 2, [fill], List[Int](), n)
		bytes := parse_string(args)?
		var bs = bytes.clone()
		if word == ".asciz": bs.append(0)
		return self.add_data(line, 1, List[String](), bs.clone(), bs.length())
	return error(Error("unknown directive '{word}'"))

fn var Ctx.instruction(line: Int, word: String, args: String) Unit!:
	if self.in_data: return error(Error("instruction in data section"))
	op := mnemonic_op(word)
	if op < 0: return error(Error("unknown mnemonic '{word}'"))
	texts := split_operands(args)
	var ops = List[Opnd]()
	for t in texts:
		ops.append(parse_operand(t)?)
	if ops.length() != arity(op): return error(Error("wrong number of operands for '{word}'"))
	if not classes_ok(op, ops): return error(Error("invalid operands for '{word}'"))
	self.instrs.append(Instr(op, word, line, ops))
	self.items.append(Item(line, true, self.instrs.length() - 1))
	return ok(unit)

fn var Ctx.pass1_line(line: Int, raw: String) Unit!:
	var rest = strip_comment(raw).trim()
	while rest != "":
		cs := rest.chars().clone()
		if not is_ident_start(cs[0]): break
		var j = 0
		while j < cs.length() and is_ident_char(cs[j]): j += 1
		if j < cs.length() and cs[j] == ":":
			self.define_label(sub(cs, 0, j))?
			rest = sub(cs, j + 1, cs.length()).trim()
		else: break
	if rest == "": return ok(unit)
	cs := rest.chars()
	var j = 0
	while j < cs.length() and cs[j] != " " and cs[j] != "\t": j += 1
	word := sub(cs, 0, j)
	args := sub(cs, j, cs.length()).trim()
	if word.starts_with("."): return self.directive(line, word, args)
	return self.instruction(line, word, args)

fn var Ctx.pass2() Unit!:
	var mem = List[Int]()
	for i in 0..4096:
		mem.append(0)
	self.mem = mem
	n := self.instrs.length()
	for ii in 0..self.items.length():
		it := self.items[ii].clone()
		self.cur_line = it.line
		if not it.is_instr:
			d := self.ditems[it.idx].clone()
			if d.kind == 0:
				for k in 0..d.exprs.length():
					v := self.eval_top(d.exprs[k])?
					self.mem.set(d.addr + k, v)
			else if d.kind == 1:
				for k in 0..d.bytes.length():
					self.mem.set(d.addr + k, d.bytes[k])
			else:
				v := self.eval_top(d.exprs[0])?
				for k in 0..d.count:
					self.mem.set(d.addr + k, v)
		else:
			ins := self.instrs[it.idx].clone()
			var ks = [3, 3]
			var rs = [0, 0]
			var vs = [0, 0]
			for j in 0..ins.ops.length():
				o := ins.ops[j]
				if o.kind == 0:
					ks.set(j, 0)
					rs.set(j, o.reg)
				else if o.kind == 1:
					ks.set(j, 1)
					vs.set(j, self.eval_top(o.text)?)
				else:
					ks.set(j, 2)
					rs.set(j, o.reg)
					if o.text != "": vs.set(j, self.eval_top(o.text)?)
			if ins.op >= 20 and ins.op <= 27:
				t := vs[0]
				if t < 0 or t >= n: return error(Error("invalid jump target"))
			self.p_op.append(ins.op)
			self.p_ln.append(ins.line)
			self.p_ak.append(ks[0])
			self.p_ar.append(rs[0])
			self.p_av.append(vs[0])
			self.p_bk.append(ks[1])
			self.p_br.append(rs[1])
			self.p_bv.append(vs[1])
	return ok(unit)

type Vm:
	regs: List[Int]
	mem: List[Int]
	trap: String = ""

fn Vm.addr(r: Int, v: Int) Int:
	if r >= 0: return wrap(v + self.regs[r])
	return v

fn var Vm.rd(k: Int, r: Int, v: Int) Int:
	if k == 0: return self.regs[r]
	if k == 1: return v
	a := self.addr(r, v)
	if a < 0 or a >= 4096:
		self.trap = "memory access out of range: {a}"
		return 0
	return self.mem[a]

fn var Vm.wr(k: Int, r: Int, v: Int, val: Int) Unit:
	if k == 0:
		self.regs.set(r, val)
		return
	a := self.addr(r, v)
	if a < 0 or a >= 4096:
		self.trap = "memory access out of range: {a}"
		return
	self.mem.set(a, val)

fn var Vm.store(a: Int, val: Int) Unit:
	if a < 0 or a >= 4096:
		self.trap = "memory access out of range: {a}"
		return
	self.mem.set(a, val)

fn parse_inputs(text: String) List[Int]:
	var out = List[Int]()
	for tok in text.fields():
		cs := tok.chars()
		var start = 0
		var neg = false
		if cs[0] == "-":
			neg = true
			start = 1
		if start >= cs.length(): continue
		var good = true
		var v = 0
		for i in start..cs.length():
			if not is_digit(cs[i]):
				good = false
				break
			v = bit_and(v * 10 + (code(cs[i]) - 48), 4294967295)
		if not good: continue
		out.append(wrap(if neg: -v else: v))
	return out

fn run(ctx: Ctx, input: List[Int]) String:
	n := ctx.p_op.length()
	var vm = Vm(regs: [0, 0, 0, 0, 0, 0, 0, 0, 4096, 0], mem: ctx.mem.clone())
	var out = List[String]()
	var ascii = List[String]()
	for i in 0..128:
		ascii.append(from_scalars([i]).get(""))
	var pc = if ctx.main_pc >= 0: ctx.main_pc else: 0
	var steps = 0
	var z = false
	var l = false
	var inp = 0
	var halted = false
	var trap_pc = 0
	budget := ctx.budget
	while true:
		if pc < 0 or pc >= n:
			vm.trap = "pc out of range"
			trap_pc = pc
			break
		if steps == budget:
			vm.trap = "budget exceeded"
			trap_pc = pc
			break
		o := ctx.p_op[pc]
		ak := ctx.p_ak[pc]
		ar := ctx.p_ar[pc]
		av := ctx.p_av[pc]
		bk := ctx.p_bk[pc]
		br := ctx.p_br[pc]
		bv := ctx.p_bv[pc]
		var next = pc + 1
		if o == 0:
			val := vm.rd(bk, br, bv)
			if vm.trap == "": vm.wr(ak, ar, av, val)
		else if o <= 12:
			s := vm.rd(bk, br, bv)
			if vm.trap == "":
				d := vm.regs[ar]
				if o == 1: vm.regs.set(ar, wrap(d + s))
				else if o == 2: vm.regs.set(ar, wrap(d - s))
				else if o == 3: vm.regs.set(ar, wrap(d * s))
				else if o == 4:
					if s == 0: vm.trap = "division by zero"
					else: vm.regs.set(ar, wrap(d / s))
				else if o == 5:
					if s == 0: vm.trap = "division by zero"
					else: vm.regs.set(ar, wrap(d % s))
				else if o == 6: vm.regs.set(ar, bit_and(d, s))
				else if o == 7: vm.regs.set(ar, bit_or(d, s))
				else if o == 8: vm.regs.set(ar, bit_xor(d, s))
				else if o == 9: vm.regs.set(ar, wrap(shift_left(d, bit_and(s, 31))))
				else if o == 10: vm.regs.set(ar, shift_right_unsigned(bit_and(d, 4294967295), bit_and(s, 31)))
				else if o == 11: vm.regs.set(ar, shift_right(d, bit_and(s, 31)))
				else:
					z = d == s
					l = d < s
		else if o == 13: vm.regs.set(ar, wrap(0 - vm.regs[ar]))
		else if o == 14: vm.regs.set(ar, bit_not(vm.regs[ar]))
		else if o == 15: vm.regs.set(ar, wrap(vm.regs[ar] + 1))
		else if o == 16: vm.regs.set(ar, wrap(vm.regs[ar] - 1))
		else if o == 17: vm.regs.set(ar, vm.addr(br, bv))
		else if o == 18:
			v := vm.rd(ak, ar, av)
			if vm.trap == "":
				if vm.regs[8] <= 0: vm.trap = "stack overflow"
				else:
					sp := vm.regs[8] - 1
					vm.regs.set(8, sp)
					vm.store(sp, v)
		else if o == 19:
			if vm.regs[8] >= 4096: vm.trap = "stack underflow"
			else:
				a := vm.regs[8]
				if a < 0:
					vm.trap = "memory access out of range: {a}"
				else:
					vm.regs.set(8, a + 1)
					vm.regs.set(ar, vm.mem[a])
		else if o >= 20 and o <= 26:
			var take = true
			if o == 21: take = z
			else if o == 22: take = not z
			else if o == 23: take = l
			else if o == 24: take = l or z
			else if o == 25: take = not l and not z
			else if o == 26: take = not l
			if take: next = av
		else if o == 27:
			if vm.regs[8] <= 0: vm.trap = "stack overflow"
			else:
				sp := vm.regs[8] - 1
				vm.regs.set(8, sp)
				vm.store(sp, pc + 1)
				if vm.trap == "": next = av
		else if o == 28:
			if vm.regs[8] >= 4096: vm.trap = "stack underflow"
			else:
				a := vm.regs[8]
				if a < 0:
					vm.trap = "memory access out of range: {a}"
				else:
					vm.regs.set(8, a + 1)
					next = vm.mem[a]
		else if o == 29:
			if inp >= input.length(): vm.trap = "input exhausted"
			else:
				vm.regs.set(ar, input[inp])
				inp += 1
		else if o == 30:
			v := vm.rd(ak, ar, av)
			if vm.trap == "": out.append("{v}\n")
		else if o == 31:
			v := vm.rd(ak, ar, av)
			if vm.trap == "":
				if v < 0 or v > 127: vm.trap = "invalid character"
				else: out.append(ascii[v].clone())
		else if o == 32:
			halted = true
			steps += 1
			break
		if vm.trap != "":
			trap_pc = pc
			break
		steps += 1
		pc = next
	var text = out.join("")
	if text != "" and not text.ends_with("\n"): text += "\n"
	if halted:
		text += "-- halted after {steps} steps\n"
	else:
		line := if vm.trap == "pc out of range": "-" else: "{ctx.p_ln[trap_pc]}"
		text += "-- trap: {vm.trap} (pc={trap_pc} line={line}) after {steps} steps\n"
	text += "regs: r0={vm.regs[0]} r1={vm.regs[1]} r2={vm.regs[2]} r3={vm.regs[3]} r4={vm.regs[4]} r5={vm.regs[5]} r6={vm.regs[6]} r7={vm.regs[7]} sp={vm.regs[8]} bp={vm.regs[9]}\n"
	zi := if z: 1 else: 0
	li := if l: 1 else: 0
	text += "flags: Z={zi} L={li}\n"
	return text

fn main_run(src_lines: List[String], input: List[Int]) String:
	var ctx = Ctx()
	for i in 0..src_lines.length():
		r := ctx.pass1_line(i + 1, src_lines[i])
		if not r.is_ok():
			return "asm error line {i + 1}: {r.err().message}\n"
	r2 := ctx.pass2()
	if not r2.is_ok():
		return "asm error line {ctx.cur_line}: {r2.err().message}\n"
	return run(ctx, input)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	b := read_all(stdin(), none)?
	s := b.decode_utf8().get("")
	all := s.lines()
	var src = List[String]()
	var rest = List[String]()
	var seen = false
	for ln in all:
		if seen: rest.append(ln.clone())
		else if ln == "====": seen = true
		else: src.append(ln.clone())
	input := parse_inputs(rest.join(" "))
	print(main_run(src, input), end: "")
