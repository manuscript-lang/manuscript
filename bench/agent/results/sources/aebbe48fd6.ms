import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import wrapping_add, wrapping_multiply, wrapping_subtract from "@std/math/math.ms"

enum Value:
	N(n: Int)
	B(b: Bool)
	S(id: Int)
	Y(id: Int)
	Nil
	Void
	Pair(id: Int)
	Proc(id: Int)
	Bi(id: Int)
	Tail

// tags: N1 B2 S3 Y4 Nil5 Void6 Pair7 Proc8 Bi9 Tail10
fn tag(v: Value) Int:
	match v:
		N(_x): return 1
		B(_x): return 2
		S(_x): return 3
		Y(_x): return 4
		Nil: return 5
		Void: return 6
		Pair(_x): return 7
		Proc(_x): return 8
		Bi(_x): return 9
		Tail: return 10

fn pay(v: Value) Int:
	match v:
		N(x): return x
		B(x): return if x: 1 else: 0
		S(x): return x
		Y(x): return x
		Pair(x): return x
		Proc(x): return x
		Bi(x): return x
		_: return 0

fn pid(v: Value) Int:
	match v:
		Pair(x): return x
		_: return -1

fn symid(v: Value) Int:
	match v:
		Y(x): return x
		_: return -1

fn truthy(v: Value) Bool:
	return not (tag(v) == 2 and pay(v) == 0)

fn is_proc(v: Value) Bool:
	t := tag(v)
	return t == 8 or t == 9

fn synerr(msg: String) Error:
	return Error("syntax error: {msg}", kind: "syntax")

fn rterr(msg: String) Error:
	return Error(msg)

fn is_delim(c: Int) Bool:
	return c == -1 or c == 32 or c == 9 or c == 10 or c == 13 or c == 40 or c == 41 or c == 34 or c == 59

fn int_min() Int: -9223372036854775807 - 1

fn add_i(a: Int, b: Int) Int!:
	r := wrapping_add(a, b)
	if (a >= 0) == (b >= 0) and (r >= 0) != (a >= 0):
		return error(rterr("integer overflow"))
	return ok(r)

fn sub_i(a: Int, b: Int) Int!:
	r := wrapping_subtract(a, b)
	if (a >= 0) != (b >= 0) and (r >= 0) != (a >= 0):
		return error(rterr("integer overflow"))
	return ok(r)

fn mul_i(a: Int, b: Int) Int!:
	if a == 0 or b == 0: return ok(0)
	if a == -1:
		if b == int_min(): return error(rterr("integer overflow"))
		return ok(-b)
	if b == -1:
		if a == int_min(): return error(rterr("integer overflow"))
		return ok(-a)
	r := wrapping_multiply(a, b)
	if r / a != b:
		return error(rterr("integer overflow"))
	return ok(r)

type Interp:
	src: String = ""
	pos: Int = 0
	strs: List[String] = []
	syms: List[String] = []
	symmap: Map[String, Int] = Map[String, Int]()
	gslot: List[Int] = []
	cars: List[Value] = []
	cdrs: List[Value] = []
	b_sym: List[Int] = []
	b_val: List[Value] = []
	b_next: List[Int] = []
	fr_parent: List[Int] = []
	fr_head: List[Int] = []
	cl_pstart: List[Int] = []
	cl_pcount: List[Int] = []
	cl_rest: List[Int] = []
	cl_env: List[Int] = []
	cl_name: List[Int] = []
	cl_body: List[Value] = []
	plist: List[Int] = []
	bi_name: List[String] = []
	bi_min: List[Int] = []
	bi_max: List[Int] = []
	bi_grp: List[Int] = []
	depth: Int = 0
	tail_e: Value = Value.Nil
	tail_env: Int = 0
	enter: Bool = false
	parts: List[String] = []
	any_out: Bool = false
	last_nl: Bool = true

fn var Interp.intern(name: String) Int:
	if id := self.symmap.get(name):
		return id
	id := self.syms.length()
	self.syms.append(name.clone())
	self.symmap[name.clone()] = id
	self.gslot.append(-1)
	return id

fn var Interp.mkstr(s: String) Value:
	self.strs.append(s.clone())
	return Value.S(self.strs.length() - 1)

fn var Interp.cons(a: Value, b: Value) Value:
	self.cars.append(a)
	self.cdrs.append(b)
	return Value.Pair(self.cars.length() - 1)

fn var Interp.vec_to_list(items: List[Value], tail: Value) Value:
	var r = tail
	var i = items.length() - 1
	while i >= 0:
		r = self.cons(items[i], r)
		i -= 1
	return r

fn Interp.list_to_vec(v: Value) List[Value]?:
	var out = List[Value]()
	var cur = v
	while true:
		p := pid(cur)
		if p < 0: break
		out.append(self.cars[p])
		cur = self.cdrs[p]
	if tag(cur) != 5: return none
	return out

fn Interp.is_proper(v: Value) Bool:
	var cur = v
	while true:
		p := pid(cur)
		if p < 0: break
		cur = self.cdrs[p]
	return tag(cur) == 5

fn var Interp.reg(grp: Int, name: String, mn: Int, mx: Int) Unit:
	id := self.bi_name.length()
	self.bi_name.append(name.clone())
	self.bi_min.append(mn)
	self.bi_max.append(mx)
	self.bi_grp.append(grp)
	s := self.intern(name)
	self.bind_global(s, Value.Bi(id))

fn var Interp.bind_global(sym: Int, val: Value) Unit:
	b := self.gslot[sym]
	if b >= 0:
		self.b_val.set(b, val)
		return
	self.b_sym.append(sym)
	self.b_val.append(val)
	self.b_next.append(-1)
	self.gslot.set(sym, self.b_sym.length() - 1)

fn var Interp.new_frame(parent: Int) Int:
	self.fr_parent.append(parent)
	self.fr_head.append(-1)
	return self.fr_parent.length() - 1

fn var Interp.bind_new(f: Int, sym: Int, val: Value) Unit:
	if f == 0:
		self.bind_global(sym, val)
		return
	self.b_sym.append(sym)
	self.b_val.append(val)
	self.b_next.append(self.fr_head[f])
	self.fr_head.set(f, self.b_sym.length() - 1)

fn var Interp.bind(f: Int, sym: Int, val: Value) Unit:
	if f == 0:
		self.bind_global(sym, val)
		return
	var b = self.fr_head[f]
	while b >= 0:
		if self.b_sym[b] == sym:
			self.b_val.set(b, val)
			return
		b = self.b_next[b]
	self.bind_new(f, sym, val)

fn Interp.find(sym: Int, env: Int) Int:
	var f = env
	while f != 0:
		var b = self.fr_head[f]
		while b >= 0:
			if self.b_sym[b] == sym: return b
			b = self.b_next[b]
		f = self.fr_parent[f]
	return self.gslot[sym]

fn Interp.lookup(sym: Int, env: Int) Value!:
	b := self.find(sym, env)
	if b < 0:
		return error(rterr("unbound variable: {self.syms[sym]}"))
	return ok(self.b_val[b])

// ---------- output ----------

fn var Interp.out(s: String) Unit:
	if s.length() == 0: return
	self.parts.append(s.clone())
	self.any_out = true
	self.last_nl = s.ends_with("\n")

fn Interp.quote_str(s: String) String:
	var out = List[String]()
	out.append("\"")
	for c in s.chars():
		if c == "\\": out.append("\\\\")
		else if c == "\"": out.append("\\\"")
		else if c == "\n": out.append("\\n")
		else if c == "\t": out.append("\\t")
		else: out.append(c.clone())
	out.append("\"")
	return out.join("")

fn Interp.emit(v: Value, quote: Bool, var out: List[String]) Unit:
	t := tag(v)
	if t == 1: out.append("{pay(v)}")
	else if t == 2: out.append(if pay(v) == 1: "#t" else: "#f")
	else if t == 3:
		if quote: out.append(self.quote_str(self.strs[pay(v)]))
		else: out.append(self.strs[pay(v)].clone())
	else if t == 4: out.append(self.syms[pay(v)].clone())
	else if t == 5: out.append("()")
	else if t == 6: out.append("#<void>")
	else if t == 7: self.emit_pair(pay(v), quote, var out)
	else if t == 8:
		n := self.cl_name[pay(v)]
		if n >= 0: out.append("#<procedure {self.syms[n]}>")
		else: out.append("#<procedure>")
	else if t == 9: out.append("#<builtin {self.bi_name[pay(v)]}>")
	else: out.append("#<tail>")

fn Interp.emit_pair(id: Int, quote: Bool, var out: List[String]) Unit:
	out.append("(")
	var cur = id
	while true:
		self.emit(self.cars[cur], quote, var out)
		nxt := self.cdrs[cur]
		np := pid(nxt)
		if np >= 0:
			out.append(" ")
			cur = np
			continue
		if tag(nxt) != 5:
			out.append(" . ")
			self.emit(nxt, quote, var out)
		break
	out.append(")")

fn Interp.repr(v: Value, quote: Bool) String:
	var out = List[String]()
	self.emit(v, quote, var out)
	return out.join("")

// ---------- reader ----------

fn Interp.peek() Int:
	return self.src.scalar_at(self.pos, -1)

fn var Interp.skip_ws() Unit:
	while true:
		c := self.peek()
		if c == 32 or c == 9 or c == 10 or c == 13:
			self.pos += 1
		else if c == 59:
			while true:
				d := self.peek()
				if d == -1 or d == 10: break
				self.pos += 1
		else:
			break

fn var Interp.read_datum() Value!:
	self.skip_ws()
	c := self.peek()
	if c == -1: return error(synerr("unexpected end of input"))
	if c == 41:
		self.pos += 1
		return error(synerr("unexpected )"))
	if c == 40:
		self.pos += 1
		return self.read_list()
	if c == 39:
		self.pos += 1
		d := self.read_datum()?
		q := Value.Y(0)
		return ok(self.cons(q, self.cons(d, Value.Nil)))
	if c == 34:
		self.pos += 1
		return self.read_string()
	return self.read_atom()

fn var Interp.read_list() Value!:
	var items = List[Value]()
	while true:
		self.skip_ws()
		c := self.peek()
		if c == -1: return error(synerr("unexpected end of input"))
		if c == 41:
			self.pos += 1
			return ok(self.vec_to_list(items, Value.Nil))
		if c == 46 and is_delim(self.src.scalar_at(self.pos + 1, -1)):
			self.pos += 1
			if items.length() == 0: return error(synerr("bad dotted list"))
			tailv := self.read_datum()?
			self.skip_ws()
			c2 := self.peek()
			if c2 == -1: return error(synerr("unexpected end of input"))
			if c2 != 41: return error(synerr("bad dotted list"))
			self.pos += 1
			return ok(self.vec_to_list(items, tailv))
		items.append(self.read_datum()?)
	return ok(Value.Nil)

fn var Interp.read_string() Value!:
	var buf = List[String]()
	while true:
		c := self.peek()
		if c == -1: return error(synerr("unterminated string"))
		self.pos += 1
		if c == 34: break
		if c == 92:
			e := self.peek()
			if e == -1: return error(synerr("unterminated string"))
			self.pos += 1
			if e == 110: buf.append("\n")
			else if e == 116: buf.append("\t")
			else if e == 92: buf.append("\\")
			else if e == 34: buf.append("\"")
			else: return error(synerr("bad escape"))
		else:
			buf.append(self.src.slice(self.pos - 1, self.pos)?)
	return ok(self.mkstr(buf.join("")))

fn var Interp.read_atom() Value!:
	start := self.pos
	while not is_delim(self.peek()):
		self.pos += 1
	text := self.src.slice(start, self.pos)?
	if text == "#t": return ok(Value.B(true))
	if text == "#f": return ok(Value.B(false))
	var i = 0
	if text.scalar_at(0, -1) == 45: i = 1
	var digits = 0
	var all = true
	while true:
		c := text.scalar_at(i, -1)
		if c == -1: break
		if c >= 48 and c <= 57: digits += 1
		else: all = false
		i += 1
	if all and digits > 0:
		if n := text.parse_int():
			return ok(Value.N(n))
		return error(synerr("integer out of range"))
	if text == ".": return error(synerr("unexpected ."))
	if text.starts_with("#"): return error(synerr("bad token: {text}"))
	return ok(Value.Y(self.intern(text)))

// ---------- evaluator ----------

fn var Interp.eval(e: Value, env: Int) Value!:
	d := self.depth
	r := self.run(e, env, false)
	self.depth = d
	return r

fn var Interp.set_tail(e: Value, env: Int) Value:
	self.tail_e = e
	self.tail_env = env
	return Value.Tail

fn var Interp.body_tail(body: Value, env: Int) Value!:
	var cur = body
	while true:
		p := pid(cur)
		nxt := self.cdrs[p]
		if pid(nxt) < 0:
			return ok(self.set_tail(self.cars[p], env))
		_r := self.eval(self.cars[p], env)?
		cur = nxt
	return ok(Value.Void)

fn Interp.arity_msg(name: String, mn: Int, mx: Int, got: Int) String:
	var e = ""
	if mx < 0: e = "at least {mn}"
	else if mn == mx: e = "{mn}"
	else: e = "{mn} to {mx}"
	return "wrong number of arguments to {name}: expected {e}, got {got}"

fn var Interp.bind_args(cid: Int, args: List[Value]) Int!:
	n := self.cl_pcount[cid]
	rest := self.cl_rest[cid]
	got := args.length()
	if (rest < 0 and got != n) or got < n:
		nm := self.cl_name[cid]
		name := if nm >= 0: self.syms[nm].clone() else: "lambda"
		return error(rterr(self.arity_msg(name, n, if rest < 0: n else: -1, got)))
	f := self.new_frame(self.cl_env[cid])
	st := self.cl_pstart[cid]
	for i in 0..n:
		self.bind_new(f, self.plist[st + i], args[i])
	if rest >= 0:
		var lst = Value.Nil
		var j = got - 1
		while j >= n:
			lst = self.cons(args[j], lst)
			j -= 1
		self.bind_new(f, rest, lst)
	return ok(f)

fn var Interp.run(e0: Value, env0: Int, counted0: Bool) Value!:
	var e = e0
	var env = env0
	var counted = counted0
	while true:
		sid := symid(e)
		if sid >= 0: return self.lookup(sid, env)
		p := pid(e)
		if p < 0:
			if tag(e) == 5: return error(synerr("empty application"))
			return ok(e)
		head := self.cars[p]
		hs := symid(head)
		if hs >= 0 and hs <= 14:
			r := self.special(hs, e, env)?
			if tag(r) == 10:
				e = self.tail_e
				env = self.tail_env
				if self.enter:
					self.enter = false
					if not counted:
						if self.depth >= 10000: return error(rterr("recursion limit exceeded"))
						self.depth += 1
						counted = true
				continue
			return ok(r)
		if not self.is_proper(e): return error(synerr("bad application"))
		f := self.eval(head, env)?
		var args = List[Value]()
		var cur = self.cdrs[p]
		while true:
			q := pid(cur)
			if q < 0: break
			args.append(self.eval(self.cars[q], env)?)
			cur = self.cdrs[q]
		ft := tag(f)
		if ft == 8:
			cid := pay(f)
			nenv := self.bind_args(cid, args)?
			if not counted:
				if self.depth >= 10000: return error(rterr("recursion limit exceeded"))
				self.depth += 1
				counted = true
			_r := self.body_tail(self.cl_body[cid], nenv)?
			e = self.tail_e
			env = self.tail_env
			continue
		if ft == 9: return self.call_builtin(pay(f), args)
		return error(rterr("not a procedure: {self.repr(f, true)}"))
	return ok(Value.Void)

fn var Interp.apply_proc(f: Value, args: List[Value]) Value!:
	ft := tag(f)
	if ft == 9: return self.call_builtin(pay(f), args)
	if ft == 8:
		cid := pay(f)
		d := self.depth
		nenv := self.bind_args(cid, args)?
		if d >= 10000: return error(rterr("recursion limit exceeded"))
		self.depth = d + 1
		_r := self.body_tail(self.cl_body[cid], nenv)?
		r := self.run(self.tail_e, self.tail_env, true)
		self.depth = d
		return r
	return error(rterr("not a procedure: {self.repr(f, true)}"))

fn badform(name: String) Error:
	return synerr("bad form: {name}")

// Creates a closure; returns -1 when the parameter list is invalid.
fn var Interp.new_closure(params: Value, body: Value, env: Int, name: Int) Int:
	var ids = List[Int]()
	var rest = -1
	var cur = params
	while true:
		p := pid(cur)
		if p < 0: break
		s := symid(self.cars[p])
		if s < 0 or ids.contains(s): return -1
		ids.append(s)
		cur = self.cdrs[p]
	if tag(cur) == 4:
		s := symid(cur)
		if ids.contains(s): return -1
		rest = s
	else if tag(cur) != 5:
		return -1
	self.cl_pstart.append(self.plist.length())
	self.cl_pcount.append(ids.length())
	for s in ids:
		self.plist.append(s)
	self.cl_rest.append(rest)
	self.cl_env.append(env)
	self.cl_name.append(name)
	self.cl_body.append(body)
	return self.cl_pstart.length() - 1

fn var Interp.do_lambda(form: Value, env: Int, name: Int) Value!:
	// form = (lambda params body...)
	p := pid(form)
	r1 := self.cdrs[p]
	if pid(r1) < 0: return error(badform("lambda"))
	q := pid(r1)
	body := self.cdrs[q]
	if pid(body) < 0 or not self.is_proper(body): return error(badform("lambda"))
	cid := self.new_closure(self.cars[q], body, env, name)
	if cid < 0: return error(badform("lambda"))
	return ok(Value.Proc(cid))

fn Interp.is_lambda_form(v: Value) Bool:
	p := pid(v)
	if p < 0: return false
	return symid(self.cars[p]) == 4

// Validates a let-style binding list; returns (names, init exprs).
fn Interp.parse_bindings(v: Value, form: String) List[Value]!:
	// returns flat list [name, init, name, init...]
	var out = List[Value]()
	items := self.list_to_vec(v)
	if items.is_none(): return error(badform(form))
	for b in items.get(List[Value]()):
		pair := self.list_to_vec(b)
		if pair.is_none(): return error(badform(form))
		bp := pair.get(List[Value]())
		if bp.length() != 2 or symid(bp[0]) < 0: return error(badform(form))
		out.append(bp[0])
		out.append(bp[1])
	return ok(out)

fn var Interp.special(hs: Int, e: Value, env: Int) Value!:
	name := self.syms[hs].clone()
	iv := self.list_to_vec(e)
	if iv.is_none(): return error(badform(name))
	items := iv.get(List[Value]())
	n := items.length()
	p := pid(e)
	if hs == 0:
		if n != 2: return error(badform(name))
		return ok(items[1])
	if hs == 1:
		if n != 3 and n != 4: return error(badform(name))
		t := self.eval(items[1], env)?
		if truthy(t): return ok(self.set_tail(items[2], env))
		if n == 4: return ok(self.set_tail(items[3], env))
		return ok(Value.Void)
	if hs == 2: return self.sf_define(items, e, env)
	if hs == 3:
		if n != 3 or symid(items[1]) < 0: return error(badform(name))
		v := self.eval(items[2], env)?
		b := self.find(symid(items[1]), env)
		if b < 0: return error(rterr("unbound variable: {self.syms[symid(items[1])]}"))
		self.b_val.set(b, v)
		return ok(Value.Void)
	if hs == 4:
		if n < 3: return error(badform(name))
		return self.do_lambda(e, env, -1)
	if hs == 5:
		if n == 1: return ok(Value.Void)
		return self.body_tail(self.cdrs[p], env)
	if hs == 6: return self.sf_let(items, e, env)
	if hs == 7 or hs == 8:
		if n < 3: return error(badform(name))
		bs := self.parse_bindings(items[1], name)?
		f := self.new_frame(env)
		var i = 0
		while i < bs.length():
			v := self.eval(bs[i + 1], f)?
			self.bind(f, symid(bs[i]), v)
			i += 2
		return self.body_tail(self.cdrs[pid(self.cdrs[p])], f)
	if hs == 9: return self.sf_cond(items, env)
	if hs == 10 or hs == 11:
		if n == 1: return ok(Value.B(hs == 10))
		for i in 1..(n - 1):
			v := self.eval(items[i], env)?
			if hs == 10 and not truthy(v): return ok(v)
			if hs == 11 and truthy(v): return ok(v)
		return ok(self.set_tail(items[n - 1], env))
	if hs == 12 or hs == 13:
		if n < 3: return error(badform(name))
		t := self.eval(items[1], env)?
		fire := if hs == 12: truthy(t) else: not truthy(t)
		if not fire: return ok(Value.Void)
		return self.body_tail(self.cdrs[pid(self.cdrs[p])], env)
	// try
	if n != 3: return error(badform(name))
	d := self.depth
	r := self.eval(items[1], env)
	if v := r:
		return ok(v)
	else:
		err := r.err()
		if err.kind.get("") == "syntax": return error(err)
		self.depth = d
		h := self.eval(items[2], env)?
		msg := self.mkstr(err.message)
		return self.apply_proc(h, [msg])

fn var Interp.sf_define(items: List[Value], e: Value, env: Int) Value!:
	n := items.length()
	if n < 3: return error(badform("define"))
	target := items[1]
	s := symid(target)
	if s >= 0:
		if n != 3: return error(badform("define"))
		var v = Value.Nil
		if self.is_lambda_form(items[2]):
			v = self.do_lambda(items[2], env, s)?
		else:
			v = self.eval(items[2], env)?
		self.bind(env, s, v)
		return ok(Value.Void)
	tp := pid(target)
	if tp < 0: return error(badform("define"))
	fname := symid(self.cars[tp])
	if fname < 0: return error(badform("define"))
	body := self.cdrs[pid(self.cdrs[pid(e)])]
	if not self.is_proper(body): return error(badform("define"))
	cid := self.new_closure(self.cdrs[tp], body, env, fname)
	if cid < 0: return error(badform("define"))
	self.bind(env, fname, Value.Proc(cid))
	return ok(Value.Void)

fn var Interp.sf_let(items: List[Value], e: Value, env: Int) Value!:
	n := items.length()
	if n < 3: return error(badform("let"))
	p := pid(e)
	if symid(items[1]) >= 0:
		if n < 4: return error(badform("let"))
		bs := self.parse_bindings(items[2], "let")?
		var names = List[Value]()
		var args = List[Value]()
		var i = 0
		while i < bs.length():
			names.append(bs[i])
			i += 2
		// validate before evaluating
		plist := self.vec_to_list(names, Value.Nil)
		body := self.cdrs[pid(self.cdrs[pid(self.cdrs[p])])]
		e1 := self.new_frame(env)
		cid := self.new_closure(plist, body, e1, symid(items[1]))
		if cid < 0: return error(badform("let"))
		i = 0
		while i < bs.length():
			args.append(self.eval(bs[i + 1], env)?)
			i += 2
		self.bind_new(e1, symid(items[1]), Value.Proc(cid))
		nenv := self.bind_args(cid, args)?
		_r := self.body_tail(body, nenv)?
		self.enter = true
		return ok(Value.Tail)
	bs := self.parse_bindings(items[1], "let")?
	var vals = List[Value]()
	var i = 0
	while i < bs.length():
		vals.append(self.eval(bs[i + 1], env)?)
		i += 2
	f := self.new_frame(env)
	i = 0
	while i < bs.length():
		self.bind(f, symid(bs[i]), vals[i / 2])
		i += 2
	return self.body_tail(self.cdrs[pid(self.cdrs[p])], f)

fn var Interp.sf_cond(items: List[Value], env: Int) Value!:
	n := items.length()
	for i in 1..n:
		cl := self.list_to_vec(items[i])
		if cl.is_none(): return error(badform("cond"))
		c := cl.get(List[Value]())
		if c.length() == 0: return error(badform("cond"))
		if symid(c[0]) == 15:
			if i != n - 1 or c.length() < 2: return error(badform("cond"))
			return self.body_tail(self.cdrs[pid(items[i])], env)
		t := self.eval(c[0], env)?
		if truthy(t):
			if c.length() == 1: return ok(t)
			return self.body_tail(self.cdrs[pid(items[i])], env)
	return ok(Value.Void)

// ---------- builtins ----------

fn Interp.type_err(name: String, kind: String, v: Value) Error:
	return rterr("{name}: expected {kind}, got {self.repr(v, true)}")

fn Interp.want_int(name: String, v: Value) Int!:
	if tag(v) != 1: return error(self.type_err(name, "integer", v))
	return ok(pay(v))

fn Interp.want_str(name: String, v: Value) String!:
	if tag(v) != 3: return error(self.type_err(name, "string", v))
	return ok(self.strs[pay(v)].clone())

fn Interp.want_list(name: String, v: Value) List[Value]!:
	if items := self.list_to_vec(v):
		return ok(items)
	return error(self.type_err(name, "list", v))

fn Interp.want_proc(name: String, v: Value) Unit!:
	if not is_proc(v): return error(self.type_err(name, "procedure", v))
	return ok(unit)

fn Interp.want_pair(name: String, v: Value) Int!:
	p := pid(v)
	if p < 0: return error(self.type_err(name, "pair", v))
	return ok(p)

fn var Interp.call_builtin(id: Int, args: List[Value]) Value!:
	name := self.bi_name[id].clone()
	n := args.length()
	mn := self.bi_min[id]
	mx := self.bi_max[id]
	if n < mn or (mx >= 0 and n > mx):
		return error(rterr(self.arity_msg(name, mn, mx, n)))
	g := self.bi_grp[id]
	if g == 0: return self.b_num(name, args)
	if g == 1: return self.b_pred(name, args)
	if g == 2: return self.b_list(name, args)
	if g == 3: return self.b_hof(name, args)
	if g == 4: return self.b_str(name, args)
	return self.b_other(name, args)

fn var Interp.b_num(name: String, args: List[Value]) Value!:
	n := args.length()
	if name == "+" or name == "*":
		var acc = if name == "+": 0 else: 1
		for a in args:
			x := self.want_int(name, a)?
			acc = if name == "+": add_i(acc, x)? else: mul_i(acc, x)?
		return ok(Value.N(acc))
	if name == "-":
		first := self.want_int(name, args[0])?
		if n == 1: return ok(Value.N(sub_i(0, first)?))
		var acc = first
		for i in 1..n:
			x := self.want_int(name, args[i])?
			acc = sub_i(acc, x)?
		return ok(Value.N(acc))
	var xs = List[Int]()
	for a in args:
		xs.append(self.want_int(name, a)?)
	if name == "quotient" or name == "remainder" or name == "modulo":
		a := xs[0]
		b := xs[1]
		if b == 0: return error(rterr("division by zero"))
		if name == "quotient":
			if a == int_min() and b == -1: return error(rterr("integer overflow"))
			return ok(Value.N(a / b))
		if b == -1: return ok(Value.N(0))
		r := a % b
		if name == "modulo" and r != 0 and (r < 0) != (b < 0): return ok(Value.N(r + b))
		return ok(Value.N(r))
	if name == "abs":
		if xs[0] == int_min(): return error(rterr("integer overflow"))
		return ok(Value.N(if xs[0] < 0: -xs[0] else: xs[0]))
	if name == "min" or name == "max":
		var m = xs[0]
		for x in xs:
			if name == "min" and x < m: m = x
			if name == "max" and x > m: m = x
		return ok(Value.N(m))
	if name == "zero?": return ok(Value.B(xs[0] == 0))
	if name == "even?": return ok(Value.B(xs[0] % 2 == 0))
	if name == "odd?": return ok(Value.B(xs[0] % 2 != 0))
	for i in 0..(n - 1):
		a := xs[i]
		b := xs[i + 1]
		var okc = false
		if name == "=": okc = a == b
		else if name == "<": okc = a < b
		else if name == ">": okc = a > b
		else if name == "<=": okc = a <= b
		else: okc = a >= b
		if not okc: return ok(Value.B(false))
	return ok(Value.B(true))

fn Interp.eqv(a: Value, b: Value) Bool:
	t := tag(a)
	if t != tag(b): return false
	if t == 1 or t == 2 or t == 4: return pay(a) == pay(b)
	return t == 5

fn Interp.equal(a: Value, b: Value) Bool:
	var x = a
	var y = b
	while true:
		px := pid(x)
		py := pid(y)
		if px >= 0 and py >= 0:
			if not self.equal(self.cars[px], self.cars[py]): return false
			x = self.cdrs[px]
			y = self.cdrs[py]
			continue
		if px >= 0 or py >= 0: return false
		t := tag(x)
		if t != tag(y): return false
		if t == 3: return self.strs[pay(x)] == self.strs[pay(y)]
		if t == 5 or t == 6: return true
		return pay(x) == pay(y)
	return false

fn var Interp.b_pred(name: String, args: List[Value]) Value!:
	a := args[0]
	t := tag(a)
	if name == "not": return ok(Value.B(not truthy(a)))
	if name == "null?": return ok(Value.B(t == 5))
	if name == "pair?": return ok(Value.B(t == 7))
	if name == "list?": return ok(Value.B(self.is_proper(a)))
	if name == "number?": return ok(Value.B(t == 1))
	if name == "string?": return ok(Value.B(t == 3))
	if name == "symbol?": return ok(Value.B(t == 4))
	if name == "boolean?": return ok(Value.B(t == 2))
	if name == "procedure?": return ok(Value.B(is_proc(a)))
	if name == "eq?": return ok(Value.B(self.eqv(a, args[1])))
	return ok(Value.B(self.equal(a, args[1])))

fn var Interp.b_list(name: String, args: List[Value]) Value!:
	n := args.length()
	if name == "cons": return ok(self.cons(args[0], args[1]))
	if name == "car":
		p := self.want_pair(name, args[0])?
		return ok(self.cars[p])
	if name == "cdr":
		p := self.want_pair(name, args[0])?
		return ok(self.cdrs[p])
	if name == "cadr" or name == "cddr" or name == "caddr":
		p1 := self.want_pair(name, args[0])?
		v1 := self.cdrs[p1]
		p2 := self.want_pair(name, v1)?
		if name == "cadr": return ok(self.cars[p2])
		if name == "cddr": return ok(self.cdrs[p2])
		v2 := self.cdrs[p2]
		p3 := self.want_pair(name, v2)?
		return ok(self.cars[p3])
	if name == "set-car!" or name == "set-cdr!":
		p := self.want_pair(name, args[0])?
		if name == "set-car!": self.cars.set(p, args[1])
		else: self.cdrs.set(p, args[1])
		return ok(Value.Void)
	if name == "list": return ok(self.vec_to_list(args, Value.Nil))
	if name == "length":
		items := self.want_list(name, args[0])?
		return ok(Value.N(items.length()))
	if name == "append":
		if n == 0: return ok(Value.Nil)
		var result = args[n - 1]
		var i = n - 2
		while i >= 0:
			items := self.want_list(name, args[i])?
			result = self.vec_to_list(items, result)
			i -= 1
		return ok(result)
	if name == "reverse":
		items := self.want_list(name, args[0])?
		var r = Value.Nil
		for x in items:
			r = self.cons(x, r)
		return ok(r)
	if name == "list-ref" or name == "list-tail":
		items := self.want_list(name, args[0])?
		k := self.want_int(name, args[1])?
		lim := if name == "list-ref": items.length() - 1 else: items.length()
		if k < 0 or k > lim: return error(rterr("{name}: index out of range"))
		if name == "list-ref": return ok(items[k])
		var cur = args[0]
		for _i in 0..k:
			cur = self.cdrs[pid(cur)]
		return ok(cur)
	if name == "range":
		a := self.want_int(name, args[0])?
		b := self.want_int(name, args[1])?
		var items = List[Value]()
		var i = a
		while i < b:
			items.append(Value.N(i))
			i += 1
		return ok(self.vec_to_list(items, Value.Nil))
	// assoc, member
	items := self.want_list(name, args[1])?
	for x in items:
		if name == "assoc":
			xp := self.want_pair(name, x)?
			if self.equal(self.cars[xp], args[0]): return ok(x)
		else:
			if self.equal(x, args[0]): return ok(self.member_tail(args[1], args[0]))
	return ok(Value.B(false))

fn Interp.member_tail(lst: Value, key: Value) Value:
	var cur = lst
	while true:
		p := pid(cur)
		if p < 0: break
		if self.equal(self.cars[p], key): return cur
		cur = self.cdrs[p]
	return Value.B(false)

fn var Interp.msort(items: List[Value], f: Value) List[Value]!:
	n := items.length()
	if n <= 1: return ok(items.clone())
	half := n / 2
	var l0 = List[Value]()
	var r0 = List[Value]()
	for i in 0..n:
		if i < half: l0.append(items[i])
		else: r0.append(items[i])
	l := self.msort(l0, f)?
	r := self.msort(r0, f)?
	var out = List[Value]()
	var i = 0
	var j = 0
	while i < l.length() and j < r.length():
		t := self.apply_proc(f, [r[j], l[i]])?
		if truthy(t):
			out.append(r[j])
			j += 1
		else:
			out.append(l[i])
			i += 1
	while i < l.length():
		out.append(l[i])
		i += 1
	while j < r.length():
		out.append(r[j])
		j += 1
	return ok(out)

fn var Interp.b_hof(name: String, args: List[Value]) Value!:
	n := args.length()
	if name == "sort":
		self.want_proc(name, args[1])?
		items := self.want_list(name, args[0])?
		sorted := self.msort(items, args[1])?
		return ok(self.vec_to_list(sorted, Value.Nil))
	f := args[0]
	self.want_proc(name, f)?
	if name == "map" or name == "for-each":
		var lists = List[List[Value]]()
		for i in 1..n:
			lists.append(self.want_list(name, args[i])?)
		var m = lists[0].length()
		for l in lists:
			if l.length() < m: m = l.length()
		var out = List[Value]()
		for i in 0..m:
			var a = List[Value]()
			for l in lists:
				a.append(l[i])
			r := self.apply_proc(f, a)?
			if name == "map": out.append(r)
		if name == "map": return ok(self.vec_to_list(out, Value.Nil))
		return ok(Value.Void)
	if name == "filter":
		items := self.want_list(name, args[1])?
		var out = List[Value]()
		for x in items:
			r := self.apply_proc(f, [x])?
			if truthy(r): out.append(x)
		return ok(self.vec_to_list(out, Value.Nil))
	if name == "fold" or name == "foldr":
		items := self.want_list(name, args[2])?
		var acc = args[1]
		if name == "fold":
			for x in items:
				acc = self.apply_proc(f, [acc, x])?
		else:
			var i = items.length() - 1
			while i >= 0:
				acc = self.apply_proc(f, [items[i], acc])?
				i -= 1
		return ok(acc)
	// apply
	last := self.want_list(name, args[n - 1])?
	var a = List[Value]()
	for i in 1..(n - 1):
		a.append(args[i])
	for x in last:
		a.append(x)
	return self.apply_proc(f, a)

fn var Interp.b_str(name: String, args: List[Value]) Value!:
	if name == "string-append":
		var buf = List[String]()
		for a in args:
			buf.append(self.want_str(name, a)?)
		return ok(self.mkstr(buf.join("")))
	if name == "string->symbol":
		s := self.want_str(name, args[0])?
		return ok(Value.Y(self.intern(s)))
	if name == "symbol->string":
		if tag(args[0]) != 4: return error(self.type_err(name, "symbol", args[0]))
		return ok(self.mkstr(self.syms[pay(args[0])].clone()))
	if name == "number->string":
		x := self.want_int(name, args[0])?
		return ok(self.mkstr("{x}"))
	if name == "list->string":
		items := self.want_list(name, args[0])?
		var buf = List[String]()
		for x in items:
			buf.append(self.want_str(name, x)?)
		return ok(self.mkstr(buf.join("")))
	if name == "string-join":
		items := self.want_list(name, args[0])?
		sep := self.want_str(name, args[1])?
		var buf = List[String]()
		for x in items:
			buf.append(self.want_str(name, x)?)
		return ok(self.mkstr(buf.join(sep)))
	s := self.want_str(name, args[0])?
	len := s.length()
	if name == "string-length": return ok(Value.N(len))
	if name == "string-upcase": return ok(self.mkstr(s.upper()))
	if name == "string-downcase": return ok(self.mkstr(s.lower()))
	if name == "string->list":
		var items = List[Value]()
		for i in 0..len:
			items.append(self.mkstr(s.slice(i, i + 1)?))
		return ok(self.vec_to_list(items, Value.Nil))
	if name == "string->number":
		var i = 0
		if s.scalar_at(0, -1) == 45: i = 1
		var digits = 0
		var all = true
		while i < len:
			c := s.scalar_at(i, -1)
			if c >= 48 and c <= 57: digits += 1
			else: all = false
			i += 1
		if all and digits > 0:
			if x := s.parse_int(): return ok(Value.N(x))
		return ok(Value.B(false))
	if name == "substring":
		a := self.want_int(name, args[1])?
		b := self.want_int(name, args[2])?
		if a < 0 or a > b or b > len: return error(rterr("substring: index out of range"))
		return ok(self.mkstr(s.slice(a, b)?))
	if name == "string-ref":
		i := self.want_int(name, args[1])?
		if i < 0 or i >= len: return error(rterr("string-ref: index out of range"))
		return ok(self.mkstr(s.slice(i, i + 1)?))
	t := self.want_str(name, args[1])?
	if name == "string=?": return ok(Value.B(s == t))
	if name == "string<?": return ok(Value.B(s < t))
	if name == "string-contains?": return ok(Value.B(s.contains(t)))
	// string-split
	if t.length() != 1: return error(rterr("string-split: separator must be one character"))
	var items = List[Value]()
	for piece in s.split(t):
		items.append(self.mkstr(piece))
	return ok(self.vec_to_list(items, Value.Nil))

fn var Interp.b_other(name: String, args: List[Value]) Value!:
	if name == "display":
		self.out(self.repr(args[0], false))
		return ok(Value.Void)
	if name == "write":
		self.out(self.repr(args[0], true))
		return ok(Value.Void)
	if name == "newline":
		self.out("\n")
		return ok(Value.Void)
	if name == "void": return ok(Value.Void)
	// error
	msg := self.want_str(name, args[0])?
	var buf = List[String]()
	buf.append(msg)
	for i in 1..args.length():
		buf.append(self.repr(args[i], true))
	return error(rterr(buf.join(" ")))

fn var Interp.setup(text: String) Unit:
	self.src = text.clone()
	// frame 0: global
	self.fr_parent.append(-1)
	self.fr_head.append(-1)
	for s in ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try", "else"]:
		self.intern(s)
	for s in ["+:0:-1", "-:1:-1", "*:0:-1", "quotient:2:2", "remainder:2:2", "modulo:2:2", "abs:1:1", "min:1:-1", "max:1:-1", "=:2:-1", "<:2:-1", ">:2:-1", "<=:2:-1", ">=:2:-1", "zero?:1:1", "even?:1:1", "odd?:1:1"]:
		self.reg_spec(0, s)
	for s in ["not", "null?", "pair?", "list?", "number?", "string?", "symbol?", "boolean?", "procedure?"]:
		self.reg(1, s, 1, 1)
	self.reg(1, "eq?", 2, 2)
	self.reg(1, "equal?", 2, 2)
	for s in ["cons:2:2", "car:1:1", "cdr:1:1", "cadr:1:1", "cddr:1:1", "caddr:1:1", "set-car!:2:2", "set-cdr!:2:2", "list:0:-1", "length:1:1", "append:0:-1", "reverse:1:1", "list-ref:2:2", "list-tail:2:2", "range:2:2", "assoc:2:2", "member:2:2"]:
		self.reg_spec(2, s)
	for s in ["map:2:-1", "for-each:2:-1", "filter:2:2", "fold:3:3", "foldr:3:3", "apply:2:-1", "sort:2:2"]:
		self.reg_spec(3, s)
	for s in ["string-length:1:1", "string-append:0:-1", "substring:3:3", "string-ref:2:2", "string=?:2:2", "string<?:2:2", "string-upcase:1:1", "string-downcase:1:1", "string->number:1:1", "number->string:1:1", "string->symbol:1:1", "symbol->string:1:1", "string->list:1:1", "list->string:1:1", "string-join:2:2", "string-split:2:2", "string-contains?:2:2"]:
		self.reg_spec(4, s)
	for s in ["display:1:1", "write:1:1", "newline:0:0", "void:0:0", "error:1:-1"]:
		self.reg_spec(5, s)

fn var Interp.reg_spec(grp: Int, spec: String) Unit:
	// name may itself contain ':' only never; split from the right
	parts := spec.split(":")
	cnt := parts.length()
	mn := parts[cnt - 2].parse_int().get(0)
	mx := parts[cnt - 1].parse_int().get(0)
	var nm = ""
	if cnt == 3: nm = parts[0].clone()
	self.reg(grp, nm, mn, mx)

// ---------- driver ----------

fn var Interp.finish_error(msg: String) Unit:
	if self.any_out and not self.last_nl:
		self.out("\n")
	self.out("error: {msg}\n")

// ms: allow_effect std.console.write
fn Interp.flush() Unit:
	print(self.parts.join(""), end: "")

// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var it = Interp()
	it.setup(text)
	while true:
		it.skip_ws()
		if it.peek() == -1: break
		rd := it.read_datum()
		if form := rd:
			ev := it.eval(form, 0)
			if _v := ev:
				continue
			else:
				it.finish_error(ev.err().message)
				break
		else:
			it.finish_error(rd.err().message)
			break
	it.flush()
