import BytesBuilder from "@std/bytes.ms"
import stdin, stdout_bytes from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import bit_and, bit_or, bit_xor, bit_not from "@std/math/math.ms"

type Term:
	sign: Int
	name: String
	val: Int
	big: Bool

type Opnd:
	kind: Int
	reg: Int
	text: String
	signs: List[Int]
	terms: List[String]

type Rop:
	kind: Int
	reg: Int
	val: Int

type Stmt:
	kind: Int
	line: Int
	op: Int
	ops: List[Opnd]
	addr: Int
	data: List[Int]
	count: Int

type Ev:
	labels: Map[String, Int]
	equs: Map[String, String]
	busy: Set[String]

type Prog:
	opc: List[Int]
	ak: List[Int]
	ar: List[Int]
	av: List[Int]
	bk: List[Int]
	br: List[Int]
	bv: List[Int]
	ln: List[Int]
	mem: List[Int]

fn wrap(x: Int) Int:
	m := x % 4294967296
	if m >= 2147483648: return m - 4294967296
	if m < -2147483648: return m + 4294967296
	return m

fn is_ws(c: Int) Bool: c == 32 or (c >= 9 and c <= 13)
fn is_digit(c: Int) Bool: c >= 48 and c <= 57
fn is_idstart(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
fn is_idchar(c: Int) Bool: is_idstart(c) or is_digit(c) or c == 46

fn bstr(bs: List[Int], a: Int, b: Int) String:
	var bb = BytesBuilder()
	var i = a
	while i < b:
		if v := bs[i].to_uint8():
			bb.append(v)
		i += 1
	return bb.build().decode_utf8().get("")

fn trim(bs: List[Int]) List[Int]:
	var a = 0
	var b = bs.length()
	while a < b and is_ws(bs[a]): a += 1
	while b > a and is_ws(bs[b - 1]): b -= 1
	var out = List[Int]()
	for i in a..b:
		out.append(bs[i])
	return out

fn sub(bs: List[Int], a: Int, b: Int) List[Int]:
	var out = List[Int]()
	for i in a..b:
		out.append(bs[i])
	return out

fn tobytes(s: String) List[Int]:
	var out = List[Int]()
	for v in s.as_bytes().values():
		out.append(v.to_int())
	return out

fn reg_index(s: String) Int:
	if s == "r0": return 0
	if s == "r1": return 1
	if s == "r2": return 2
	if s == "r3": return 3
	if s == "r4": return 4
	if s == "r5": return 5
	if s == "r6": return 6
	if s == "r7": return 7
	if s == "sp": return 8
	if s == "bp": return 9
	return -1

fn escape_val(c: Int) Int:
	if c == 110: return 10
	if c == 116: return 9
	if c == 48: return 0
	if c == 92: return 92
	if c == 39: return 39
	if c == 34: return 34
	return -1

// If a char literal starts at i, index of its closing quote; else -1.
fn lit_end(bs: List[Int], i: Int) Int:
	n := bs.length()
	if i >= n or bs[i] != 39: return -1
	if i + 1 < n and bs[i + 1] == 92:
		if i + 3 < n and bs[i + 3] == 39 and escape_val(bs[i + 2]) >= 0: return i + 3
		return -1
	if i + 2 < n and bs[i + 2] == 39 and bs[i + 1] != 92: return i + 2
	return -1

fn skipws(bs: List[Int], i: Int) Int:
	var j = i
	while j < bs.length() and is_ws(bs[j]): j += 1
	return j

fn digit_val(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55
	return -1

fn parse_number(bs: List[Int], a: Int, b: Int) Term?:
	var radix = 10
	var s = a
	if b - a >= 2 and bs[a] == 48 and bs[a + 1] == 120:
		radix = 16
		s = a + 2
	else if b - a >= 2 and bs[a] == 48 and bs[a + 1] == 98:
		radix = 2
		s = a + 2
	if s >= b: return none
	var v = 0
	for i in s..b:
		d := digit_val(bs[i])
		if d < 0 or d >= radix: return none
		v = v * radix + d
		if v > 4294967295: v = 4294967296
	if v > 4294967295: return Term(sign: 1, name: "", val: 0, big: true)
	return Term(sign: 1, name: "", val: wrap(v), big: false)

fn parse_expr(bs: List[Int]) List[Term]?:
	n := bs.length()
	var i = skipws(bs, 0)
	var terms = List[Term]()
	var sign = 1
	if i < n and (bs[i] == 43 or bs[i] == 45):
		if bs[i] == 45: sign = -1
		i += 1
	while true:
		i = skipws(bs, i)
		if i >= n: return none
		c := bs[i]
		if c == 39:
			e := lit_end(bs, i)
			if e < 0: return none
			var v = bs[i + 1]
			if v == 92: v = escape_val(bs[i + 2])
			terms.append(Term(sign: sign, name: "", val: v, big: false))
			i = e + 1
		else if is_digit(c):
			var j = i
			while j < n and is_idchar(bs[j]): j += 1
			t := parse_number(bs, i, j)
			if tt := t:
				terms.append(Term(sign: sign, name: "", val: tt.val, big: tt.big))
			else: return none
			i = j
		else if is_idstart(c):
			var j = i
			while j < n and is_idchar(bs[j]): j += 1
			terms.append(Term(sign: sign, name: bstr(bs, i, j), val: 0, big: false))
			i = j
		else: return none
		i = skipws(bs, i)
		if i >= n: break
		if bs[i] == 43: sign = 1
		else if bs[i] == 45: sign = -1
		else: return none
		i += 1
	return terms

fn var Ev.eval(text: String) Int!:
	bs := trim(tobytes(text))
	pe := parse_expr(bs)
	if terms := pe:
		var total = 0
		for t in terms:
			var v = 0
			if t.big: return error(Error("immediate out of range"))
			if t.name == "":
				v = t.val
			else:
				if l := self.labels.get(t.name):
					v = l
				else if e0 := self.equs.get(t.name):
					e := e0.clone()
					if self.busy.contains(t.name):
						return error(Error("circular definition of '{t.name}'"))
					self.busy.add(t.name.clone())
					r := self.eval(e)
					self.busy.remove(t.name)
					v = r?
				else:
					return error(Error("undefined symbol '{t.name}'"))
			total += t.sign * v
		return ok(wrap(total))
	return error(Error("invalid expression '{bstr(bs, 0, bs.length())}'"))

fn split_ops(bs: List[Int]) List[List[Int]]:
	var out = List[List[Int]]()
	if bs.length() == 0: return out
	n := bs.length()
	var cur = 0
	var in_br = false
	var i = 0
	while i < n:
		c := bs[i]
		e := lit_end(bs, i)
		if e >= 0:
			i = e + 1
			continue
		if c == 91: in_br = true
		else if c == 93: in_br = false
		else if c == 44 and not in_br:
			out.append(trim(sub(bs, cur, i)))
			cur = i + 1
		i += 1
	out.append(trim(sub(bs, cur, n)))
	return out

fn bad_operand(bs: List[Int]) Error:
	return Error("invalid operand '{bstr(bs, 0, bs.length())}'")

fn parse_operand(bs: List[Int]) Opnd!:
	n := bs.length()
	if n == 0: return error(bad_operand(bs))
	text := bstr(bs, 0, n)
	r := reg_index(text)
	if r >= 0:
		return ok(Opnd(kind: 0, reg: r, text: text, signs: List[Int](), terms: List[String]()))
	if bs[0] != 91:
		return ok(Opnd(kind: 1, reg: -1, text: text, signs: List[Int](), terms: List[String]()))
	if bs[n - 1] != 93: return error(bad_operand(bs))
	inner := sub(bs, 1, n - 1)
	m := inner.length()
	var i = 0
	while i < m:
		e := lit_end(inner, i)
		if e >= 0:
			i = e + 1
			continue
		if inner[i] == 91 or inner[i] == 93: return error(bad_operand(bs))
		i += 1
	var signs = List[Int]()
	var terms = List[String]()
	var base = -1
	i = skipws(inner, 0)
	var sign = 1
	if i < m and (inner[i] == 43 or inner[i] == 45):
		if inner[i] == 45: sign = -1
		i += 1
	while true:
		var j = i
		while j < m:
			e := lit_end(inner, j)
			if e >= 0:
				j = e + 1
				continue
			if inner[j] == 43 or inner[j] == 45: break
			j += 1
		t := trim(sub(inner, i, j))
		if t.length() == 0: return error(bad_operand(bs))
		ts := bstr(t, 0, t.length())
		ri := reg_index(ts)
		if ri >= 0:
			if sign < 0 or base >= 0: return error(bad_operand(bs))
			base = ri
		else:
			signs.append(sign)
			terms.append(ts)
		if j >= m: break
		sign = if inner[j] == 45: -1 else: 1
		i = j + 1
	return ok(Opnd(kind: 2, reg: base, text: text, signs: signs, terms: terms))

fn opcode_table() Map[String, Int]:
	var m = Map[String, Int]()
	names := ["mov", "add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr", "sar", "cmp", "neg", "not", "inc", "dec", "lea", "push", "pop", "jmp", "je", "jne", "jl", "jle", "jg", "jge", "call", "ret", "in", "out", "outc", "halt", "nop"]
	for i in 0..names.length():
		m[names.get(i, "")] = i
	m["jz"] = 21
	m["jnz"] = 22
	return m

// shape: 0 none, 1 mov, 2 R+RIM, 3 R, 4 R+M, 5 RIM, 6 I
fn shape(op: Int) Int:
	if op == 0: return 1
	if op >= 1 and op <= 12: return 2
	if op == 13 or op == 14 or op == 15 or op == 16 or op == 19 or op == 29: return 3
	if op == 17: return 4
	if op == 18 or op == 30 or op == 31: return 5
	if op >= 20 and op <= 27: return 6
	return 0

fn shape_count(s: Int) Int:
	if s == 0: return 0
	if s == 1 or s == 2 or s == 4: return 2
	return 1

fn classes_ok(s: Int, ops: List[Opnd]) Bool:
	if s == 1:
		a := ops[0].kind
		b := ops[1].kind
		if a == 1: return false
		if a == 2 and b == 2: return false
		return true
	if s == 2: return ops[0].kind == 0
	if s == 3: return ops[0].kind == 0
	if s == 4: return ops[0].kind == 0 and ops[1].kind == 2
	if s == 6: return ops[0].kind == 1
	return true

fn is_identifier(bs: List[Int]) Bool:
	if bs.length() == 0 or not is_idstart(bs[0]): return false
	for c in bs:
		if not is_idchar(c): return false
	return true

fn strip_line(raw: List[Int]) List[Int]:
	var q = 0
	var i = 0
	var end = raw.length()
	while i < raw.length():
		c := raw[i]
		if q != 0:
			if c == 92: i += 1
			else if c == q: q = 0
		else:
			if c == 34 or c == 39: q = c
			else if c == 59:
				end = i
				break
		i += 1
	return trim(sub(raw, 0, end))

fn parse_string(bs: List[Int]) List[Int]?:
	n := bs.length()
	if n < 2 or bs[0] != 34: return none
	var out = List[Int]()
	var i = 1
	while i < n:
		c := bs[i]
		if c == 34:
			if i == n - 1: return out
			return none
		if c == 92:
			if i + 1 >= n: return none
			v := escape_val(bs[i + 1])
			if v < 0: return none
			out.append(v)
			i += 2
		else:
			out.append(c)
			i += 1
	return none

type Asm:
	ev: Ev
	stmts: List[Stmt]
	defined: Set[String]
	ops: Map[String, Int]
	in_data: Bool = false
	ninstr: Int = 0
	dsize: Int = 0
	budget: Int = 100000
	main_idx: Int = -1

fn var Asm.define(name: String) Unit!:
	if reg_index(name) >= 0: return error(Error("reserved name '{name}'"))
	if self.defined.contains(name): return error(Error("duplicate symbol '{name}'"))
	self.defined.add(name)

fn mk_stmt(kind: Int, line: Int) Stmt:
	return Stmt(kind: kind, line: line, op: 0, ops: List[Opnd](), addr: 0, data: List[Int](), count: 0)

fn wrong_count(name: String) Error:
	return Error("wrong number of operands for '{name}'")

fn var Asm.grow(k: Int) Unit!:
	if self.dsize + k > 4096: return error(Error("data section too large"))
	self.dsize += k

fn var Asm.line(lineno: Int, bs: List[Int]) Unit!:
	var cur = bs
	// labels
	while true:
		var j = 0
		while j < cur.length() and is_idchar(cur[j]): j += 1
		if j > 0 and is_idstart(cur[0]) and j < cur.length() and cur[j] == 58:
			name := bstr(cur, 0, j)
			self.define(name.clone())?
			if name == "main" and not self.in_data and self.main_idx < 0:
				self.main_idx = self.ninstr
			self.ev.labels[name] = if self.in_data: self.dsize else: self.ninstr
			cur = trim(sub(cur, j + 1, cur.length()))
		else: break
	if cur.length() == 0: return ok(unit)
	var w = 0
	while w < cur.length() and not is_ws(cur[w]): w += 1
	word := bstr(cur, 0, w)
	rest := trim(sub(cur, w, cur.length()))
	if cur[0] == 46:
		return self.directive(lineno, word, rest)
	// instruction
	if self.in_data: return error(Error("instruction in data section"))
	opo := self.ops.get(word)
	if opo.is_none(): return error(Error("unknown mnemonic '{word}'"))
	op := opo.get(0)
	pieces := split_ops(rest)
	var parsed = List[Opnd]()
	for p in pieces:
		o := parse_operand(p)?
		parsed.append(o)
	sh := shape(op)
	if parsed.length() != shape_count(sh): return error(wrong_count(word))
	if not classes_ok(sh, parsed): return error(Error("invalid operands for '{word}'"))
	var st = mk_stmt(0, lineno)
	st.op = op
	st.ops = parsed
	self.stmts.append(st)
	self.ninstr += 1
	return ok(unit)

fn var Asm.directive(lineno: Int, word: String, rest: List[Int]) Unit!:
	if word == ".text" or word == ".data":
		if rest.length() > 0: return error(bad_operand(rest))
		self.in_data = word == ".data"
		return ok(unit)
	if word == ".equ":
		pieces := split_ops(rest)
		if pieces.length() != 2: return error(wrong_count(".equ"))
		if not is_identifier(pieces[0]): return error(bad_operand(pieces[0]))
		name := bstr(pieces[0], 0, pieces[0].length())
		self.define(name.clone())?
		self.ev.equs[name] = bstr(pieces[1], 0, pieces[1].length())
		return ok(unit)
	if word == ".budget":
		n := rest.length()
		if n == 0 or n > 8: return error(bad_operand(rest))
		var v = 0
		for c in rest:
			if not is_digit(c): return error(bad_operand(rest))
			v = v * 10 + (c - 48)
		if v < 1 or v > 10000000: return error(bad_operand(rest))
		self.budget = v
		return ok(unit)
	is_data := word == ".word" or word == ".ascii" or word == ".asciz" or word == ".space"
	if not is_data:
		return error(Error("unknown directive '{word}'"))
	if not self.in_data: return error(Error("data directive in text section"))
	var st = mk_stmt(1, lineno)
	st.addr = self.dsize
	if word == ".word":
		pieces := split_ops(rest)
		if pieces.length() == 0: return error(wrong_count(".word"))
		var ops = List[Opnd]()
		for p in pieces:
			ops.append(Opnd(kind: 1, reg: -1, text: bstr(p, 0, p.length()), signs: List[Int](), terms: List[String]()))
		self.grow(ops.length())?
		st.ops = ops.clone()
		st.count = ops.length()
	else if word == ".space":
		pieces := split_ops(rest)
		if pieces.length() < 1 or pieces.length() > 2: return error(wrong_count(".space"))
		ntext := bstr(pieces[0], 0, pieces[0].length())
		nv := self.ev.eval(ntext)?
		if nv < 0: return error(bad_operand(pieces[0]))
		self.grow(nv)?
		st.kind = 3
		st.count = nv
		if pieces.length() == 2:
			st.ops.append(Opnd(kind: 1, reg: -1, text: bstr(pieces[1], 0, pieces[1].length()), signs: List[Int](), terms: List[String]()))
	else:
		ps := parse_string(rest)
		if data := ps:
			var d = data
			if word == ".asciz": d.append(0)
			self.grow(d.length())?
			st.kind = 2
			st.count = d.length()
			st.data = d
		else:
			return error(Error("invalid string"))
	self.stmts.append(st)
	return ok(unit)

fn resolve(var ev: Ev, o: Opnd) Rop!:
	if o.kind == 0: return ok(Rop(kind: 0, reg: o.reg, val: 0))
	if o.kind == 1:
		v := ev.eval(o.text)?
		return ok(Rop(kind: 1, reg: -1, val: v))
	var total = 0
	for i in 0..o.terms.length():
		v := ev.eval(o.terms.get(i, ""))?
		total += o.signs.get(i, 1) * v
	return ok(Rop(kind: 2, reg: o.reg, val: wrap(total)))

fn pass2(stmts: List[Stmt], var ev: Ev, var prog: Prog, ninstr: Int) Unit!:
	for s in stmts:
		r := pass2_one(s, var ev, var prog, ninstr)
		if _x := r:
			unit
		else:
			return error(Error("asm error line {s.line}: {r.err().message}"))
	return ok(unit)

fn pass2_one(s: Stmt, var ev: Ev, var prog: Prog, ninstr: Int) Unit!:
	if s.kind == 0:
		var ra = Rop(kind: 0, reg: 0, val: 0)
		var rb = Rop(kind: 0, reg: 0, val: 0)
		if s.ops.length() >= 1:
			ra = resolve(var ev, s.ops[0])?
		if s.ops.length() >= 2:
			rb = resolve(var ev, s.ops[1])?
		if shape(s.op) == 6:
			if ra.val < 0 or ra.val >= ninstr: return error(Error("invalid jump target"))
		prog.opc.append(s.op)
		prog.ak.append(ra.kind)
		prog.ar.append(ra.reg)
		prog.av.append(ra.val)
		prog.bk.append(rb.kind)
		prog.br.append(rb.reg)
		prog.bv.append(rb.val)
		prog.ln.append(s.line)
	else if s.kind == 1:
		for i in 0..s.ops.length():
			v := ev.eval(s.ops[i].text)?
			prog.mem.set(s.addr + i, v)
	else if s.kind == 2:
		for i in 0..s.data.length():
			prog.mem.set(s.addr + i, s.data[i])
	else:
		var fill = 0
		if s.ops.length() > 0:
			fill = ev.eval(s.ops[0].text)?
		for i in 0..s.count:
			prog.mem.set(s.addr + i, fill)
	return ok(unit)

type VM:
	regs: List[Int]
	mem: List[Int]
	input: List[Int]
	inpos: Int = 0
	out: BytesBuilder
	outlast: Int = -1
	outany: Bool = false
	trap: String = ""
	z: Bool = false
	l: Bool = false
	steps: Int = 0
	pc: Int = 0

fn var VM.emit(c: Int) Unit:
	if v := c.to_uint8():
		self.out.append(v)
	self.outlast = c
	self.outany = true

fn var VM.emit_str(s: String) Unit:
	for v in s.as_bytes().values():
		self.out.append(v)
		self.outlast = v.to_int()
	self.outany = true

fn var VM.ea(reg: Int, v: Int) Int:
	if reg >= 0: return wrap(self.regs[reg] + v)
	return v

fn var VM.load(addr: Int) Int:
	if addr < 0 or addr >= 4096:
		self.trap = "memory access out of range: {addr}"
		return 0
	return self.mem[addr]

fn var VM.store(addr: Int, v: Int) Unit:
	if addr < 0 or addr >= 4096:
		self.trap = "memory access out of range: {addr}"
		return
	self.mem.set(addr, v)

fn var VM.read(k: Int, r: Int, v: Int) Int:
	if k == 0: return self.regs[r]
	if k == 1: return v
	return self.load(self.ea(r, v))

fn pow2(c: Int) Int:
	var p = 1
	for _i in 0..c:
		p = p * 2
	return p

fn var VM.run(opc: List[Int], ak: List[Int], ar: List[Int], av: List[Int], bk: List[Int], br: List[Int], bv: List[Int], budget: Int) Bool:
	n := opc.length()
	while true:
		pc := self.pc
		if pc < 0 or pc >= n:
			self.trap = "pc out of range"
			return false
		if self.steps == budget:
			self.trap = "budget exceeded"
			return false
		op := opc[pc]
		a_k := ak[pc]
		a_r := ar[pc]
		a_v := av[pc]
		var next = pc + 1
		if op == 0:
			v := self.read(bk[pc], br[pc], bv[pc])
			if self.trap != "": return false
			if a_k == 0: self.regs.set(a_r, v)
			else: self.store(self.ea(a_r, a_v), v)
			if self.trap != "": return false
		else if op >= 1 and op <= 12:
			s := self.read(bk[pc], br[pc], bv[pc])
			if self.trap != "": return false
			d := self.regs[a_r]
			var res = 0
			if op == 1: res = wrap(d + s)
			else if op == 2: res = wrap(d - s)
			else if op == 3: res = wrap(d * s)
			else if op == 4 or op == 5:
				if s == 0:
					self.trap = "division by zero"
					return false
				if op == 4: res = wrap(d / s)
				else: res = wrap(d % s)
			else if op == 6: res = bit_and(d, s)
			else if op == 7: res = bit_or(d, s)
			else if op == 8: res = bit_xor(d, s)
			else if op == 9 or op == 10 or op == 11:
				c := bit_and(s, 31)
				u := bit_and(d, 4294967295)
				if op == 9: res = wrap(u * pow2(c))
				else if op == 10: res = wrap(u / pow2(c))
				else:
					if d >= 0: res = d / pow2(c)
					else: res = -((-d - 1) / pow2(c)) - 1
			if op == 12:
				self.z = d == s
				self.l = d < s
			else:
				self.regs.set(a_r, res)
		else if op == 13: self.regs.set(a_r, wrap(-self.regs[a_r]))
		else if op == 14: self.regs.set(a_r, bit_not(self.regs[a_r]))
		else if op == 15: self.regs.set(a_r, wrap(self.regs[a_r] + 1))
		else if op == 16: self.regs.set(a_r, wrap(self.regs[a_r] - 1))
		else if op == 17:
			ea17 := self.ea(br[pc], bv[pc])
			self.regs.set(a_r, ea17)
		else if op == 18 or op == 27:
			var v = next
			if op == 18:
				v = self.read(a_k, a_r, a_v)
				if self.trap != "": return false
			if self.regs[8] <= 0:
				self.trap = "stack overflow"
				return false
			self.regs.set(8, self.regs[8] - 1)
			self.store(self.regs[8], v)
			if self.trap != "": return false
			if op == 27: next = a_v
		else if op == 19 or op == 28:
			sp := self.regs[8]
			if sp >= 4096:
				self.trap = "stack underflow"
				return false
			v := self.load(sp)
			if self.trap != "": return false
			self.regs.set(8, sp + 1)
			if op == 19: self.regs.set(a_r, v)
			else: next = v
		else if op >= 20 and op <= 26:
			var take = false
			if op == 20: take = true
			else if op == 21: take = self.z
			else if op == 22: take = not self.z
			else if op == 23: take = self.l
			else if op == 24: take = self.l or self.z
			else if op == 25: take = not self.l and not self.z
			else: take = not self.l
			if take: next = a_v
		else if op == 29:
			if self.inpos >= self.input.length():
				self.trap = "input exhausted"
				return false
			self.regs.set(a_r, self.input[self.inpos])
			self.inpos += 1
		else if op == 30:
			v := self.read(a_k, a_r, a_v)
			if self.trap != "": return false
			self.emit_str("{v}\n")
		else if op == 31:
			v := self.read(a_k, a_r, a_v)
			if self.trap != "": return false
			if v < 0 or v > 127:
				self.trap = "invalid character"
				return false
			self.emit(v)
		else if op == 32:
			self.steps += 1
			return true
		self.steps += 1
		self.pc = next
	return true

fn parse_input(bs: List[Int]) List[Int]:
	var out = List[Int]()
	n := bs.length()
	var i = 0
	while i < n:
		if is_ws(bs[i]):
			i += 1
			continue
		var j = i
		while j < n and not is_ws(bs[j]): j += 1
		var s = i
		var neg = false
		if bs[s] == 45:
			neg = true
			s += 1
		var ok_tok = s < j
		var acc = 0
		for k in s..j:
			if not is_digit(bs[k]):
				ok_tok = false
				break
			acc = (acc * 10 + (bs[k] - 48)) % 4294967296
		if ok_tok:
			out.append(wrap(if neg: -acc else: acc))
		i = j
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	all := data.values()
	var lines = List[List[Int]]()
	var cur = List[Int]()
	var inp = List[Int]()
	var seen_sep = false
	var rest_start = 0
	var idx = 0
	var raw_lines = List[List[Int]]()
	while idx < all.length():
		c := all[idx].to_int()
		if c == 10:
			if cur.length() > 0 and cur[cur.length() - 1] == 13: cur.pop()
			if cur.length() == 4 and cur[0] == 61 and cur[1] == 61 and cur[2] == 61 and cur[3] == 61:
				seen_sep = true
				rest_start = idx + 1
				break
			raw_lines.append(cur)
			cur = List[Int]()
		else:
			cur.append(c)
		idx += 1
	if not seen_sep:
		if cur.length() > 0 and cur[cur.length() - 1] == 13: cur.pop()
		if cur.length() == 4 and cur[0] == 61 and cur[1] == 61 and cur[2] == 61 and cur[3] == 61:
			seen_sep = true
			rest_start = all.length()
		else:
			raw_lines.append(cur)
	if seen_sep:
		var tail = List[Int]()
		for k in rest_start..all.length():
			tail.append(all[k].to_int())
		inp = parse_input(tail)
	lines = raw_lines

	var asm = Asm(ev: Ev(labels: Map[String, Int](), equs: Map[String, String](), busy: Set[String]()), stmts: List[Stmt](), defined: Set[String](), ops: opcode_table())
	var bb = BytesBuilder()
	for i in 0..lines.length():
		bs := strip_line(lines[i])
		r := asm.line(i + 1, bs)
		if _x := r:
			unit
		else:
			bb.append_bytes("asm error line {i + 1}: {r.err().message}\n".to_bytes())
			stdout_bytes().write(bb.build())?
			return ok(unit)
	var prog = Prog(opc: List[Int](), ak: List[Int](), ar: List[Int](), av: List[Int](), bk: List[Int](), br: List[Int](), bv: List[Int](), ln: List[Int](), mem: List[Int]())
	for _i in 0..4096:
		prog.mem.append(0)
	r2 := pass2(asm.stmts, var asm.ev, var prog, asm.ninstr)
	if _x := r2:
		unit
	else:
		bb.append_bytes("{r2.err().message}\n".to_bytes())
		stdout_bytes().write(bb.build())?
		return ok(unit)
	var regs = List[Int]()
	for _i in 0..10:
		regs.append(0)
	regs.set(8, 4096)
	var vm = VM(regs: regs, mem: prog.mem.clone(), input: inp, out: BytesBuilder())
	if asm.main_idx >= 0: vm.pc = asm.main_idx
	halted := vm.run(prog.opc, prog.ak, prog.ar, prog.av, prog.bk, prog.br, prog.bv, asm.budget)
	bb.append_bytes(vm.out.build())
	if vm.outany and vm.outlast != 10:
		bb.append(10)
	var summary = ""
	if halted:
		summary = "-- halted after {vm.steps} steps\n"
	else:
		line := if vm.trap == "pc out of range": "-" else: "{prog.ln.get(vm.pc, 0)}"
		summary = "-- trap: {vm.trap} (pc={vm.pc} line={line}) after {vm.steps} steps\n"
	bb.append_bytes(summary.to_bytes())
	names := ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "sp", "bp"]
	var rl = "regs:"
	for i in 0..10:
		rl = "{rl} {names.get(i, "")}={vm.regs[i]}"
	bb.append_bytes("{rl}\n".to_bytes())
	zf := if vm.z: 1 else: 0
	lf := if vm.l: 1 else: 0
	bb.append_bytes("flags: Z={zf} L={lf}\n".to_bytes())
	stdout_bytes().write(bb.build())?
	return ok(unit)
