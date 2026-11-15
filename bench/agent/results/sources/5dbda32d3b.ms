import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import Bytes from "@std/bytes.ms"

enum Value:
	VVoid
	VNil
	VBool(b: Bool)
	VInt(n: Int)
	VSym(id: Int)
	VStr(id: Int)
	VPair(id: Int)
	VClo(id: Int)
	VBuiltin(id: Int)

type Closure:
	params: Value
	nreq: Int
	rest: Int
	body: Value
	env: Int
	name: Int

type Interp:
	syms: List[String] = []
	symmap: Map[String, Int] = Map[String, Int]()
	strs: List[String] = []
	cars: List[Value] = []
	cdrs: List[Value] = []
	gval: List[Value] = []
	gdef: List[Bool] = []
	bsym: List[Int] = []
	bval: List[Value] = []
	bnext: List[Int] = []
	fhead: List[Int] = []
	fparent: List[Int] = []
	closures: List[Closure] = []
	bnames: List[String] = []
	bmin: List[Int] = []
	bmax: List[Int] = []
	depth: Int = 0
	out: String = ""
	any_out: Bool = false
	last_nl: Bool = true
	src: Bytes = "".to_bytes()
	pos: Int = 0

let_max := 9223372036854775807
let_min := -9223372036854775807 - 1

fn err(msg: String) Value!:
	return error(Error(msg))

fn qstr(s: String) String:
	var r = "\""
	for i in 0..s.length():
		c := s.slice(i, i + 1).get("")
		if c == "\\": r += "\\\\"
		else if c == "\"": r += "\\\""
		else if c == "\n": r += "\\n"
		else if c == "\t": r += "\\t"
		else: r += c
	r += "\""
	return r

fn var Interp.intern(s: String) Int:
	if id := self.symmap.get(s):
		return id
	self.syms.append(s.clone())
	id := self.syms.length() - 1
	self.symmap[s.clone()] = id
	self.gval.append(Value.VVoid)
	self.gdef.append(false)
	return id

fn var Interp.mkstr(s: String) Value:
	self.strs.append(s)
	return Value.VStr(self.strs.length() - 1)

fn var Interp.cons(a: Value, d: Value) Value:
	self.cars.append(a)
	self.cdrs.append(d)
	return Value.VPair(self.cars.length() - 1)

fn var Interp.mklist(items: List[Value], tail: Value) Value:
	var r = tail
	var i = items.length() - 1
	while i >= 0:
		r = self.cons(items[i], r)
		i -= 1
	return r

fn Interp.show(v: Value, wr: Bool) String:
	match v:
		VVoid: return "#<void>"
		VNil: return "()"
		VBool(b): return if b: "#t" else: "#f"
		VInt(n): return "{n}"
		VSym(id): return self.syms[id].clone()
		VStr(id):
			if wr: return qstr(self.strs[id])
			return self.strs[id].clone()
		VClo(id):
			nm := self.closures[id].name
			if nm < 0: return "#<procedure>"
			return "#<procedure {self.syms[nm]}>"
		VBuiltin(id): return "#<builtin {self.bnames[id]}>"
		VPair(_):
			var s = "("
			var cur = v
			var first = true
			var going = true
			while going:
				match cur:
					VPair(p):
						if not first: s += " "
						first = false
						s += self.show(self.cars[p], wr)
						cur = self.cdrs[p]
					VNil: going = false
					_:
						s += " . " + self.show(cur, wr)
						going = false
			s += ")"
			return s

// ---------- output ----------

// ms: allow_effect std.console.write
fn var Interp.flush() Unit:
	if self.out.length() > 0:
		var o = stdout()
		_ := o.write(self.out)
		self.out = ""

fn var Interp.emit(s: String) Unit:
	if s.length() == 0: return
	self.any_out = true
	self.last_nl = s.slice(s.length() - 1, s.length()).get("") == "\n"
	self.out += s
	if self.out.length() > 60000: self.flush()

// ---------- reader ----------

fn Interp.peek() Int:
	if self.pos >= self.src.length(): return -1
	return self.src.get(self.pos).to_int()

fn is_delim(c: Int) Bool:
	return c == 32 or c == 9 or c == 10 or c == 13 or c == 40 or c == 41 or c == 34 or c == 59

fn is_ws(c: Int) Bool:
	return c == 32 or c == 9 or c == 10 or c == 13

fn var Interp.skip_ws() Unit:
	while true:
		c := self.peek()
		if c == -1: return
		if is_ws(c):
			self.pos += 1
		else if c == 59:
			while self.peek() != -1 and self.peek() != 10:
				self.pos += 1
		else:
			return

fn Interp.sub(a: Int, b: Int) String:
	return self.src.decode_utf8_range(a, b).get("")

fn var Interp.is_lone_dot() Bool:
	if self.peek() != 46: return false
	n := if self.pos + 1 >= self.src.length(): -1 else: self.src.get(self.pos + 1).to_int()
	return n == -1 or is_delim(n)

fn is_int_text(s: String) Bool:
	n := s.length()
	var i = 0
	if n > 0 and s.slice(0, 1).get("") == "-": i = 1
	if i >= n: return false
	while i < n:
		c := s.slice(i, i + 1).get("")
		if c < "0" or c > "9": return false
		i += 1
	return true

fn var Interp.read_datum() Value!:
	self.skip_ws()
	c := self.peek()
	if c == -1: return err("syntax error: unexpected end of input")
	if c == 41: return err("syntax error: unexpected )")
	if c == 40:
		self.pos += 1
		var items = List[Value]()
		var tail = Value.VNil
		while true:
			self.skip_ws()
			d := self.peek()
			if d == -1: return err("syntax error: unexpected end of input")
			if d == 41:
				self.pos += 1
				break
			if self.is_lone_dot():
				if items.length() == 0: return err("syntax error: bad dotted list")
				self.pos += 1
				self.skip_ws()
				e := self.peek()
				if e == -1: return err("syntax error: unexpected end of input")
				if e == 41: return err("syntax error: bad dotted list")
				tail = self.read_datum()?
				self.skip_ws()
				f := self.peek()
				if f == -1: return err("syntax error: unexpected end of input")
				if f != 41: return err("syntax error: bad dotted list")
				self.pos += 1
				break
			items.append(self.read_datum()?)
		return ok(self.mklist(items, tail))
	if c == 39:
		self.pos += 1
		d := self.read_datum()?
		q := self.intern("quote")
		return ok(self.cons(Value.VSym(q), self.cons(d, Value.VNil)))
	if c == 34:
		self.pos += 1
		var s = ""
		var start = self.pos
		while true:
			d := self.peek()
			if d == -1: return err("syntax error: unterminated string")
			if d == 34:
				s += self.sub(start, self.pos)
				self.pos += 1
				break
			if d == 92:
				s += self.sub(start, self.pos)
				self.pos += 1
				e := self.peek()
				if e == -1: return err("syntax error: unterminated string")
				if e == 110: s += "\n"
				else if e == 116: s += "\t"
				else if e == 92: s += "\\"
				else if e == 34: s += "\""
				else: return err("syntax error: bad escape")
				self.pos += 1
				start = self.pos
			else:
				self.pos += 1
		return ok(self.mkstr(s))
	// atom
	start := self.pos
	while self.peek() != -1 and not is_delim(self.peek()):
		self.pos += 1
	a := self.sub(start, self.pos)
	if a == ".": return err("syntax error: unexpected .")
	if a == "#t": return ok(Value.VBool(true))
	if a == "#f": return ok(Value.VBool(false))
	if a.slice(0, 1).get("") == "#": return err("syntax error: bad token: {a}")
	if is_int_text(a):
		if n := a.parse_int():
			return ok(Value.VInt(n))
		return err("syntax error: integer out of range")
	return ok(Value.VSym(self.intern(a)))

// ---------- environments ----------

fn var Interp.new_frame(parent: Int) Int:
	self.fparent.append(parent)
	self.fhead.append(-1)
	return self.fparent.length() - 1

fn var Interp.add_binding(f: Int, sym: Int, v: Value) Unit:
	self.bsym.append(sym)
	self.bval.append(v)
	self.bnext.append(self.fhead[f])
	self.fhead[f] = self.bsym.length() - 1

fn var Interp.define(env: Int, sym: Int, v: Value) Unit:
	if env == 0:
		self.gval[sym] = v
		self.gdef[sym] = true
		return
	var b = self.fhead[env]
	while b >= 0:
		if self.bsym[b] == sym:
			self.bval[b] = v
			return
		b = self.bnext[b]
	self.add_binding(env, sym, v)

fn Interp.lookup(sym: Int, env: Int) Value?:
	var f = env
	while f != 0:
		var b = self.fhead[f]
		while b >= 0:
			if self.bsym[b] == sym: return self.bval[b]
			b = self.bnext[b]
		f = self.fparent[f]
	if self.gdef[sym]: return self.gval[sym]
	return none

fn var Interp.assign(sym: Int, env: Int, v: Value) Bool:
	var f = env
	while f != 0:
		var b = self.fhead[f]
		while b >= 0:
			if self.bsym[b] == sym:
				self.bval[b] = v
				return true
			b = self.bnext[b]
		f = self.fparent[f]
	if self.gdef[sym]:
		self.gval[sym] = v
		return true
	return false

// ---------- list helpers ----------

// proper-list length or -1
fn Interp.list_len(v: Value) Int:
	var n = 0
	var cur = v
	while true:
		match cur:
			VNil: return n
			VPair(p):
				n += 1
				cur = self.cdrs[p]
			_: return -1
	return -1

fn Interp.to_vec(v: Value) List[Value]:
	var r = List[Value]()
	var cur = v
	var going = true
	while going:
		match cur:
			VPair(p):
				r.append(self.cars[p])
				cur = self.cdrs[p]
			_: going = false
	return r

fn Interp.car_of(v: Value) Value:
	match v:
		VPair(p): return self.cars[p]
		_: return Value.VVoid

fn Interp.cdr_of(v: Value) Value:
	match v:
		VPair(p): return self.cdrs[p]
		_: return Value.VVoid

fn is_pair(v: Value) Bool:
	match v:
		VPair(_): return true
		_: return false

fn is_nil(v: Value) Bool:
	match v:
		VNil: return true
		_: return false

fn Interp.is_sym(v: Value, id: Int) Bool:
	match v:
		VSym(s): return s == id
		_: return false

fn Interp.equal(a: Value, b: Value) Bool:
	match a:
		VVoid:
			match b:
				VVoid: return true
				_: return false
		VNil: return is_nil(b)
		VBool(x):
			match b:
				VBool(y): return x == y
				_: return false
		VInt(x):
			match b:
				VInt(y): return x == y
				_: return false
		VSym(x):
			match b:
				VSym(y): return x == y
				_: return false
		VStr(x):
			match b:
				VStr(y): return self.strs[x] == self.strs[y]
				_: return false
		VClo(x):
			match b:
				VClo(y): return x == y
				_: return false
		VBuiltin(x):
			match b:
				VBuiltin(y): return x == y
				_: return false
		VPair(_):
			var x = a
			var y = b
			while true:
				match x:
					VPair(p):
						match y:
							VPair(q):
								if not self.equal(self.cars[p], self.cars[q]): return false
								x = self.cdrs[p]
								y = self.cdrs[q]
							_: return false
					_: return self.equal(x, y)
			return false

fn Interp.eqp(a: Value, b: Value) Bool:
	match a:
		VNil: return is_nil(b)
		VBool(x):
			match b:
				VBool(y): return x == y
				_: return false
		VInt(x):
			match b:
				VInt(y): return x == y
				_: return false
		VSym(x):
			match b:
				VSym(y): return x == y
				_: return false
		_: return false

// ---------- closures ----------

// returns rest sym id (-1 none), -2 bad. counts required in cnt[0]
type PInfo:
	rest: Int
	n: Int

fn Interp.check_params(p: Value) PInfo:
	var seen = List[Int]()
	var cur = p
	var n = 0
	while true:
		match cur:
			VNil: return PInfo(-1, n)
			VSym(s):
				for x in seen:
					if x == s: return PInfo(-2, 0)
				return PInfo(s, n)
			VPair(q):
				match self.cars[q]:
					VSym(s):
						for x in seen:
							if x == s: return PInfo(-2, 0)
						seen.append(s)
						n += 1
					_: return PInfo(-2, 0)
				cur = self.cdrs[q]
			_: return PInfo(-2, 0)
	return PInfo(-2, 0)

fn var Interp.make_closure(params: Value, body: Value, env: Int, name: Int, form: String) Value!:
	r := self.check_params(params)
	if r.rest == -2: return err("syntax error: bad form: {form}")
	if self.list_len(body) < 1: return err("syntax error: bad form: {form}")
	self.closures.append(Closure(params, r.n, r.rest, body, env, name))
	return ok(Value.VClo(self.closures.length() - 1))

fn var Interp.bind_closure(cid: Int, args: List[Value]) Int!:
	nreq := self.closures[cid].nreq
	rest := self.closures[cid].rest
	n := args.length()
	if n < nreq or (rest == -1 and n > nreq):
		nm := self.closures[cid].name
		name := if nm < 0: "lambda" else: self.syms[nm].clone()
		exp := if rest == -1: "{nreq}" else: "at least {nreq}"
		return error(Error("wrong number of arguments to {name}: expected {exp}, got {n}"))
	f := self.new_frame(self.closures[cid].env)
	var cur = self.closures[cid].params
	var i = 0
	while i < nreq:
		self.add_binding(f, Value.VVoid.sym_of(self, cur), args[i])
		cur = self.cdr_of(cur)
		i += 1
	if rest >= 0:
		var items = List[Value]()
		while i < n:
			items.append(args[i])
			i += 1
		self.add_binding(f, rest, self.mklist(items, Value.VNil))
	return ok(f)

fn Value.sym_of(it: Interp, lst: Value) Int:
	match lst:
		VPair(p):
			match it.cars[p]:
				VSym(s): return s
				_: return 0
		_: return 0

// ---------- evaluation ----------

// special form ids
sf_quote := 0
sf_if := 1
sf_define := 2
sf_set := 3
sf_lambda := 4
sf_begin := 5
sf_let := 6
sf_letstar := 7
sf_letrec := 8
sf_cond := 9
sf_and := 10
sf_or := 11
sf_when := 12
sf_unless := 13
sf_try := 14
n_special := 15
sym_else := 15

fn Interp.badform(id: Int) Value!:
	return err("syntax error: bad form: {self.syms[id]}")

fn Interp.truthy(v: Value) Bool:
	match v:
		VBool(b): return b
		_: return true

// evaluate all but the last of a body list; return the last expression
fn var Interp.eval_seq_init(body: Value, env: Int) Value!:
	var cur = body
	while true:
		match cur:
			VPair(p):
				nx := self.cdrs[p]
				if is_pair(nx):
					_ := self.eval(self.cars[p], env)?
					cur = nx
				else:
					return ok(self.cars[p])
			_: return ok(Value.VVoid)
	return ok(Value.VVoid)

fn var Interp.eval(expr: Value, env: Int) Value!:
	base := self.depth
	r := self.eval_loop(expr, env)
	self.depth = base
	return r

fn var Interp.apply_proc(f: Value, args: List[Value]) Value!:
	match f:
		VBuiltin(id): return self.call_builtin(id, args)
		VClo(cid):
			base := self.depth
			if base + 1 > 10000: return err("recursion limit exceeded")
			self.depth = base + 1
			env := self.bind_closure(cid, args)?
			last := self.eval_seq_init(self.closures[cid].body, env)?
			r := self.eval_loop(last, env)
			self.depth = base
			return r
		_: return err("not a procedure: {self.show(f, true)}")

fn var Interp.eval_let_bindings(bindings: Value, env: Int, form: Int) Int!:
	// returns count or error; validates shape
	var cur = bindings
	var n = 0
	while true:
		match cur:
			VNil: return ok(n)
			VPair(p):
				b := self.cars[p]
				if self.list_len(b) != 2: return error(Error("syntax error: bad form: {self.syms[form]}"))
				match self.cars[self.pair_id(b)]:
					VSym(_): n += 1
					_: return error(Error("syntax error: bad form: {self.syms[form]}"))
				cur = self.cdrs[p]
			_: return error(Error("syntax error: bad form: {self.syms[form]}"))
	return ok(n)

fn Interp.pair_id(v: Value) Int:
	match v:
		VPair(p): return p
		_: return 0

fn var Interp.eval_loop(expr0: Value, env0: Int) Value!:
	var expr = expr0
	var env = env0
	var entered = false
	while true:
		match expr:
			VSym(s):
				if v := self.lookup(s, env): return ok(v)
				return err("unbound variable: {self.syms[s]}")
			VNil: return err("syntax error: empty application")
			VPair(p):
				head := self.cars[p]
				var sf = -1
				match head:
					VSym(hs):
						if hs < n_special: sf = hs
					_: sf = -1
				n := self.list_len(expr)
				if sf < 0:
					if n < 0: return err("syntax error: bad application")
					f := self.eval(head, env)?
					var args = List[Value]()
					var cur = self.cdrs[p]
					while is_pair(cur):
						args.append(self.eval(self.car_of(cur), env)?)
						cur = self.cdr_of(cur)
					match f:
						VBuiltin(id): return self.call_builtin(id, args)
						VClo(cid):
							if not entered:
								if self.depth + 1 > 10000: return err("recursion limit exceeded")
								self.depth += 1
								entered = true
							env = self.bind_closure(cid, args)?
							expr = self.eval_seq_init(self.closures[cid].body, env)?
						_: return err("not a procedure: {self.show(f, true)}")
				else:
					if n < 0: return self.badform(sf)
					a1 := self.car_of(self.cdr_of(expr))
					a2 := self.car_of(self.cdr_of(self.cdr_of(expr)))
					rest1 := self.cdr_of(expr)
					rest2 := self.cdr_of(rest1)
					if sf == sf_quote:
						if n != 2: return self.badform(sf)
						return ok(a1)
					else if sf == sf_if:
						if n != 3 and n != 4: return self.badform(sf)
						t := self.eval(a1, env)?
						if self.truthy(t):
							expr = a2
						else:
							if n == 3: return ok(Value.VVoid)
							expr = self.car_of(self.cdr_of(rest2))
					else if sf == sf_define:
						if n < 3: return self.badform(sf)
						match a1:
							VSym(name):
								if n != 3: return self.badform(sf)
								var v = Value.VVoid
								if self.is_lambda_form(a2):
									v = self.eval_lambda(a2, env, name)?
								else:
									v = self.eval(a2, env)?
								self.define(env, name, v)
								return ok(Value.VVoid)
							VPair(tp):
								match self.cars[tp]:
									VSym(name):
										v := self.make_closure(self.cdrs[tp], rest2, env, name, "define")?
										self.define(env, name, v)
										return ok(Value.VVoid)
									_: return self.badform(sf)
							_: return self.badform(sf)
					else if sf == sf_set:
						if n != 3: return self.badform(sf)
						match a1:
							VSym(name):
								v := self.eval(a2, env)?
								if not self.assign(name, env, v): return err("unbound variable: {self.syms[name]}")
								return ok(Value.VVoid)
							_: return self.badform(sf)
					else if sf == sf_lambda:
						if n < 3: return self.badform(sf)
						return self.make_closure(a1, rest2, env, -1, "lambda")
					else if sf == sf_begin:
						if n == 1: return ok(Value.VVoid)
						expr = self.eval_seq_init(rest1, env)?
					else if sf == sf_let:
						if n < 3: return self.badform(sf)
						var named = -1
						var bindings = a1
						var body = rest2
						match a1:
							VSym(nm):
								named = nm
								if n < 4: return self.badform(sf)
								bindings = a2
								body = self.cdr_of(rest2)
							_: named = -1
						cnt := self.eval_let_bindings(bindings, env, sf)?
						var names = List[Value]()
						var vals = List[Value]()
						var cur = bindings
						while is_pair(cur):
							b := self.car_of(cur)
							names.append(self.car_of(b))
							vals.append(self.eval(self.car_of(self.cdr_of(b)), env)?)
							cur = self.cdr_of(cur)
						if cnt < 0: return self.badform(sf)
						if named >= 0:
							f1 := self.new_frame(env)
							plist := self.mklist(names, Value.VNil)
							v := self.make_closure(plist, body, f1, named, "let")?
							self.add_binding(f1, named, v)
							match v:
								VClo(cid):
									if not entered:
										if self.depth + 1 > 10000: return err("recursion limit exceeded")
										self.depth += 1
										entered = true
									env = self.bind_closure(cid, vals)?
									expr = self.eval_seq_init(self.closures[cid].body, env)?
								_: return err("internal")
						else:
							if self.list_len(body) < 1: return self.badform(sf)
							f := self.new_frame(env)
							var i = 0
							while i < names.length():
								self.add_binding(f, Value.VVoid.sym_of_v(names[i]), vals[i])
								i += 1
							env = f
							expr = self.eval_seq_init(body, env)?
					else if sf == sf_letstar or sf == sf_letrec:
						if n < 3: return self.badform(sf)
						_ := self.eval_let_bindings(a1, env, sf)?
						f := self.new_frame(env)
						var cur = a1
						while is_pair(cur):
							b := self.car_of(cur)
							v := self.eval(self.car_of(self.cdr_of(b)), f)?
							self.add_binding(f, Value.VVoid.sym_of_v(self.car_of(b)), v)
							cur = self.cdr_of(cur)
						env = f
						expr = self.eval_seq_init(rest2, env)?
					else if sf == sf_cond:
						var cur = rest1
						var found = false
						while is_pair(cur):
							cl := self.car_of(cur)
							cn := self.list_len(cl)
							if cn < 1: return self.badform(sf)
							tst := self.car_of(cl)
							isLast := not is_pair(self.cdr_of(cur))
							if self.is_sym(tst, sym_else):
								if not isLast or cn < 2: return self.badform(sf)
								expr = self.eval_seq_init(self.cdr_of(cl), env)?
								found = true
								break
							t := self.eval(tst, env)?
							if self.truthy(t):
								if cn == 1: return ok(t)
								expr = self.eval_seq_init(self.cdr_of(cl), env)?
								found = true
								break
							cur = self.cdr_of(cur)
						if not found: return ok(Value.VVoid)
					else if sf == sf_and:
						if n == 1: return ok(Value.VBool(true))
						var cur = rest1
						while true:
							nx := self.cdr_of(cur)
							if is_pair(nx):
								t := self.eval(self.car_of(cur), env)?
								if not self.truthy(t): return ok(t)
								cur = nx
							else:
								expr = self.car_of(cur)
								break
					else if sf == sf_or:
						if n == 1: return ok(Value.VBool(false))
						var cur = rest1
						while true:
							nx := self.cdr_of(cur)
							if is_pair(nx):
								t := self.eval(self.car_of(cur), env)?
								if self.truthy(t): return ok(t)
								cur = nx
							else:
								expr = self.car_of(cur)
								break
					else if sf == sf_when or sf == sf_unless:
						if n < 3: return self.badform(sf)
						t := self.eval(a1, env)?
						fire := if sf == sf_when: self.truthy(t) else: not self.truthy(t)
						if not fire: return ok(Value.VVoid)
						expr = self.eval_seq_init(rest2, env)?
					else:
						// try
						if n != 3: return self.badform(sf)
						base := self.depth
						r := self.eval(a1, env)
						if v := r:
							return ok(v)
						msg := r.err().message
						if msg.length() >= 13 and msg.slice(0, 13).get("") == "syntax error:":
							return err(msg)
						self.depth = base
						h := self.eval(a2, env)?
						ms := self.mkstr(msg)
						return self.apply_proc(h, [ms])
			_: return ok(expr)
	return ok(Value.VVoid)

fn Value.sym_of_v(v: Value) Int:
	match v:
		VSym(s): return s
		_: return 0

fn Interp.is_lambda_form(v: Value) Bool:
	match v:
		VPair(p):
			match self.cars[p]:
				VSym(s): return s == sf_lambda
				_: return false
		_: return false

fn var Interp.eval_lambda(form: Value, env: Int, name: Int) Value!:
	n := self.list_len(form)
	if n < 3: return err("syntax error: bad form: lambda")
	rest := self.cdr_of(form)
	return self.make_closure(self.car_of(rest), self.cdr_of(rest), env, name, "lambda")

// ---------- builtins ----------

fn Interp.tyerr(name: String, kind: String, v: Value) Value!:
	return err("{name}: expected {kind}, got {self.show(v, true)}")

fn checked_add(a: Int, b: Int) Int?:
	if b > 0 and a > let_max - b: return none
	if b < 0 and a < let_min - b: return none
	return a + b

fn checked_sub(a: Int, b: Int) Int?:
	if b < 0 and a > let_max + b: return none
	if b > 0 and a < let_min + b: return none
	return a - b

fn checked_mul(a: Int, b: Int) Int?:
	if a == 0 or b == 0: return 0
	if a > 0:
		if b > 0:
			if a > let_max / b: return none
		else:
			if b < let_min / a: return none
	else:
		if b > 0:
			if a < let_min / b: return none
		else:
			if a < let_max / b: return none
	return a * b

fn var Interp.int_arg(name: String, v: Value) Int!:
	match v:
		VInt(n): return ok(n)
		_: return error(Error("{name}: expected integer, got {self.show(v, true)}"))

fn var Interp.str_arg(name: String, v: Value) String!:
	match v:
		VStr(id): return ok(self.strs[id].clone())
		_: return error(Error("{name}: expected string, got {self.show(v, true)}"))

fn var Interp.list_arg(name: String, v: Value) List[Value]!:
	if self.list_len(v) < 0: return error(Error("{name}: expected list, got {self.show(v, true)}"))
	return ok(self.to_vec(v))

fn var Interp.proc_arg(name: String, v: Value) Unit!:
	match v:
		VClo(_): return ok(unit)
		VBuiltin(_): return ok(unit)
		_: return error(Error("{name}: expected procedure, got {self.show(v, true)}"))

fn var Interp.pair_arg(name: String, v: Value) Int!:
	match v:
		VPair(p): return ok(p)
		_: return error(Error("{name}: expected pair, got {self.show(v, true)}"))

fn bool_v(b: Bool) Value!:
	return ok(Value.VBool(b))

fn var Interp.int_ok(r: Int?) Value!:
	if n := r: return ok(Value.VInt(n))
	return err("integer overflow")

fn var Interp.merge_sort(items: List[Value], less: Value) List[Value]!:
	n := items.length()
	if n <= 1: return ok(items)
	mid := n / 2
	var left = List[Value]()
	var right = List[Value]()
	for i in 0..n:
		if i < mid: left.append(items[i])
		else: right.append(items[i])
	l := self.merge_sort(left, less)?
	r := self.merge_sort(right, less)?
	var out = List[Value]()
	var i = 0
	var j = 0
	while i < l.length() and j < r.length():
		t := self.apply_proc(less, [r[j], l[i]])?
		if self.truthy(t):
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

fn var Interp.cxr(name: String, v: Value, path: String) Value!:
	// path applied right to left, e.g. "ad" for cadr: d first then a
	var cur = v
	var i = path.length() - 1
	while i >= 0:
		ch := path.slice(i, i + 1).get("")
		match cur:
			VPair(p):
				if ch == "a": cur = self.cars[p]
				else: cur = self.cdrs[p]
			_: return self.tyerr(name, "pair", cur)
		i -= 1
	return ok(cur)

fn var Interp.call_builtin(id: Int, args: List[Value]) Value!:
	name := self.bnames[id].clone()
	n := args.length()
	mn := self.bmin[id]
	mx := self.bmax[id]
	if n < mn or (mx >= 0 and n > mx):
		exp := if mx == mn: "{mn}" else if mx < 0: "at least {mn}" else: "{mn} to {mx}"
		return err("wrong number of arguments to {name}: expected {exp}, got {n}")
	if name == "+":
		var acc = 0
		for a in args:
			x := self.int_arg(name, a)?
			if r := checked_add(acc, x): acc = r
			else: return err("integer overflow")
		return ok(Value.VInt(acc))
	if name == "-":
		var nums = List[Int]()
		for a in args:
			nums.append(self.int_arg(name, a)?)
		if n == 1: return self.int_ok(checked_sub(0, nums[0]))
		var acc = nums[0]
		for i in 1..n:
			if r := checked_sub(acc, nums[i]): acc = r
			else: return err("integer overflow")
		return ok(Value.VInt(acc))
	if name == "*":
		var acc = 1
		for a in args:
			x := self.int_arg(name, a)?
			if r := checked_mul(acc, x): acc = r
			else: return err("integer overflow")
		return ok(Value.VInt(acc))
	if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
		var nums = List[Int]()
		for a in args:
			nums.append(self.int_arg(name, a)?)
		for i in 1..n:
			x := nums[i - 1]
			y := nums[i]
			ok_ := if name == "=": x == y else if name == "<": x < y else if name == ">": x > y else if name == "<=": x <= y else: x >= y
			if not ok_: return bool_v(false)
		return bool_v(true)
	if name == "car":
		p := self.pair_arg(name, args[0])?
		return ok(self.cars[p])
	if name == "cdr":
		p := self.pair_arg(name, args[0])?
		return ok(self.cdrs[p])
	if name == "cons": return ok(self.cons(args[0], args[1]))
	if name == "null?": return bool_v(is_nil(args[0]))
	if name == "pair?": return bool_v(is_pair(args[0]))
	if name == "not":
		match args[0]:
			VBool(b): return bool_v(not b)
			_: return bool_v(false)
	if name == "eq?": return bool_v(self.eqp(args[0], args[1]))
	if name == "equal?": return bool_v(self.equal(args[0], args[1]))
	if name == "cadr": return self.cxr(name, args[0], "ad")
	if name == "cddr": return self.cxr(name, args[0], "dd")
	if name == "caddr": return self.cxr(name, args[0], "add")
	if name == "quotient" or name == "remainder" or name == "modulo":
		a := self.int_arg(name, args[0])?
		b := self.int_arg(name, args[1])?
		if b == 0: return err("division by zero")
		if name == "quotient":
			if b == -1: return self.int_ok(checked_sub(0, a))
			return ok(Value.VInt(a / b))
		if b == -1: return ok(Value.VInt(0))
		r := a % b
		if name == "remainder": return ok(Value.VInt(r))
		if r != 0 and ((r < 0) != (b < 0)): return ok(Value.VInt(r + b))
		return ok(Value.VInt(r))
	if name == "abs":
		a := self.int_arg(name, args[0])?
		if a < 0: return self.int_ok(checked_sub(0, a))
		return ok(Value.VInt(a))
	if name == "min" or name == "max":
		var best = self.int_arg(name, args[0])?
		for i in 1..n:
			x := self.int_arg(name, args[i])?
			if name == "min" and x < best: best = x
			if name == "max" and x > best: best = x
		return ok(Value.VInt(best))
	if name == "zero?":
		a := self.int_arg(name, args[0])?
		return bool_v(a == 0)
	if name == "even?":
		a := self.int_arg(name, args[0])?
		return bool_v(a % 2 == 0)
	if name == "odd?":
		a := self.int_arg(name, args[0])?
		return bool_v(a % 2 != 0)
	if name == "list?": return bool_v(self.list_len(args[0]) >= 0)
	if name == "number?":
		match args[0]:
			VInt(_): return bool_v(true)
			_: return bool_v(false)
	if name == "string?":
		match args[0]:
			VStr(_): return bool_v(true)
			_: return bool_v(false)
	if name == "symbol?":
		match args[0]:
			VSym(_): return bool_v(true)
			_: return bool_v(false)
	if name == "boolean?":
		match args[0]:
			VBool(_): return bool_v(true)
			_: return bool_v(false)
	if name == "procedure?":
		match args[0]:
			VClo(_): return bool_v(true)
			VBuiltin(_): return bool_v(true)
			_: return bool_v(false)
	if name == "set-car!":
		p := self.pair_arg(name, args[0])?
		self.cars[p] = args[1]
		return ok(Value.VVoid)
	if name == "set-cdr!":
		p := self.pair_arg(name, args[0])?
		self.cdrs[p] = args[1]
		return ok(Value.VVoid)
	if name == "list": return ok(self.mklist(args, Value.VNil))
	if name == "length":
		items := self.list_arg(name, args[0])?
		return ok(Value.VInt(items.length()))
	if name == "append":
		if n == 0: return ok(Value.VNil)
		var all = List[Value]()
		for i in 0..n - 1:
			items := self.list_arg(name, args[i])?
			for x in items: all.append(x)
		return ok(self.mklist(all, args[n - 1]))
	if name == "reverse":
		items := self.list_arg(name, args[0])?
		var r = Value.VNil
		for x in items: r = self.cons(x, r)
		return ok(r)
	if name == "list-ref" or name == "list-tail":
		items := self.list_arg(name, args[0])?
		k := self.int_arg(name, args[1])?
		if name == "list-ref":
			if k < 0 or k >= items.length(): return err("list-ref: index out of range")
			return ok(items[k])
		if k < 0 or k > items.length(): return err("list-tail: index out of range")
		var cur = args[0]
		for _i in 0..k: cur = self.cdr_of(cur)
		return ok(cur)
	if name == "range":
		a := self.int_arg(name, args[0])?
		b := self.int_arg(name, args[1])?
		var items = List[Value]()
		var i = a
		while i < b:
			items.append(Value.VInt(i))
			i += 1
		return ok(self.mklist(items, Value.VNil))
	if name == "assoc":
		items := self.list_arg(name, args[1])?
		for e in items:
			match e:
				VPair(p):
					if self.equal(self.cars[p], args[0]): return ok(e)
				_: return self.tyerr(name, "pair", e)
		return bool_v(false)
	if name == "member":
		_ := self.list_arg(name, args[1])?
		var cur = args[1]
		while is_pair(cur):
			if self.equal(self.car_of(cur), args[0]): return ok(cur)
			cur = self.cdr_of(cur)
		return bool_v(false)
	if name == "map" or name == "for-each":
		self.proc_arg(name, args[0])?
		var lists = List[List[Value]]()
		for i in 1..n:
			lists.append(self.list_arg(name, args[i])?)
		var len = lists[0].length()
		for l in lists:
			if l.length() < len: len = l.length()
		var out = List[Value]()
		for i in 0..len:
			var call = List[Value]()
			for l in lists: call.append(l[i])
			r := self.apply_proc(args[0], call)?
			if name == "map": out.append(r)
		if name == "map": return ok(self.mklist(out, Value.VNil))
		return ok(Value.VVoid)
	if name == "filter":
		self.proc_arg(name, args[0])?
		items := self.list_arg(name, args[1])?
		var out = List[Value]()
		for x in items:
			r := self.apply_proc(args[0], [x])?
			if self.truthy(r): out.append(x)
		return ok(self.mklist(out, Value.VNil))
	if name == "fold":
		self.proc_arg(name, args[0])?
		items := self.list_arg(name, args[2])?
		var acc = args[1]
		for x in items:
			acc = self.apply_proc(args[0], [acc, x])?
		return ok(acc)
	if name == "foldr":
		self.proc_arg(name, args[0])?
		items := self.list_arg(name, args[2])?
		var acc = args[1]
		var i = items.length() - 1
		while i >= 0:
			acc = self.apply_proc(args[0], [items[i], acc])?
			i -= 1
		return ok(acc)
	if name == "apply":
		self.proc_arg(name, args[0])?
		last := self.list_arg(name, args[n - 1])?
		var call = List[Value]()
		for i in 1..n - 1: call.append(args[i])
		for x in last: call.append(x)
		return self.apply_proc(args[0], call)
	if name == "sort":
		self.proc_arg(name, args[1])?
		items := self.list_arg(name, args[0])?
		sorted := self.merge_sort(items, args[1])?
		return ok(self.mklist(sorted, Value.VNil))
	if name == "display" or name == "write":
		self.emit(self.show(args[0], name == "write"))
		return ok(Value.VVoid)
	if name == "newline":
		self.emit("\n")
		return ok(Value.VVoid)
	if name == "void": return ok(Value.VVoid)
	if name == "error":
		m := self.str_arg(name, args[0])?
		var s = m
		for i in 1..n:
			s += " " + self.show(args[i], true)
		return err(s)
	// strings
	if name == "string-length":
		s := self.str_arg(name, args[0])?
		return ok(Value.VInt(s.length()))
	if name == "string-append":
		var s = ""
		for a in args:
			s += self.str_arg(name, a)?
		return ok(self.mkstr(s))
	if name == "substring":
		s := self.str_arg(name, args[0])?
		a := self.int_arg(name, args[1])?
		b := self.int_arg(name, args[2])?
		if a < 0 or a > b or b > s.length(): return err("substring: index out of range")
		return ok(self.mkstr(s.slice(a, b).get("")))
	if name == "string-ref":
		s := self.str_arg(name, args[0])?
		k := self.int_arg(name, args[1])?
		if k < 0 or k >= s.length(): return err("string-ref: index out of range")
		return ok(self.mkstr(s.slice(k, k + 1).get("")))
	if name == "string=?" or name == "string<?":
		a := self.str_arg(name, args[0])?
		b := self.str_arg(name, args[1])?
		if name == "string=?": return bool_v(a == b)
		return bool_v(a < b)
	if name == "string-upcase" or name == "string-downcase":
		s := self.str_arg(name, args[0])?
		if name == "string-upcase": return ok(self.mkstr(s.upper()))
		return ok(self.mkstr(s.lower()))
	if name == "string->number":
		s := self.str_arg(name, args[0])?
		if is_int_text(s):
			if v := s.parse_int(): return ok(Value.VInt(v))
		return bool_v(false)
	if name == "number->string":
		a := self.int_arg(name, args[0])?
		return ok(self.mkstr("{a}"))
	if name == "string->symbol":
		s := self.str_arg(name, args[0])?
		return ok(Value.VSym(self.intern(s)))
	if name == "symbol->string":
		match args[0]:
			VSym(s): return ok(self.mkstr(self.syms[s].clone()))
			_: return self.tyerr(name, "symbol", args[0])
	if name == "string->list":
		s := self.str_arg(name, args[0])?
		var items = List[Value]()
		for i in 0..s.length():
			items.append(self.mkstr(s.slice(i, i + 1).get("")))
		return ok(self.mklist(items, Value.VNil))
	if name == "list->string":
		items := self.list_arg(name, args[0])?
		var s = ""
		for x in items: s += self.str_arg(name, x)?
		return ok(self.mkstr(s))
	if name == "string-join":
		items := self.list_arg(name, args[0])?
		sep := self.str_arg(name, args[1])?
		var s = ""
		var first = true
		for x in items:
			p := self.str_arg(name, x)?
			if not first: s += sep
			first = false
			s += p
		return ok(self.mkstr(s))
	if name == "string-split":
		s := self.str_arg(name, args[0])?
		sep := self.str_arg(name, args[1])?
		if sep.length() != 1: return err("string-split: separator must be one character")
		var items = List[Value]()
		var start = 0
		for i in 0..s.length():
			if s.slice(i, i + 1).get("") == sep:
				items.append(self.mkstr(s.slice(start, i).get("")))
				start = i + 1
		items.append(self.mkstr(s.slice(start, s.length()).get("")))
		return ok(self.mklist(items, Value.VNil))
	if name == "string-contains?":
		s := self.str_arg(name, args[0])?
		sub := self.str_arg(name, args[1])?
		return bool_v(s.contains(sub))
	return err("unbound variable: {name}")

fn var Interp.register(spec: String) Unit:
	for item in spec.split(" "):
		parts := item.split(":")
		nm := parts[0].clone()
		self.bnames.append(nm.clone())
		self.bmin.append(parts[1].parse_int().get(0))
		self.bmax.append(parts[2].parse_int().get(0))
		sym := self.intern(nm)
		self.gval[sym] = Value.VBuiltin(self.bnames.length() - 1)
		self.gdef[sym] = true

fn var Interp.setup() Unit:
	for nm in ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try", "else"]:
		_ := self.intern(nm)
	self.fparent.append(-1)
	self.fhead.append(-1)
	self.register("+:0:-1 -:1:-1 *:0:-1 quotient:2:2 remainder:2:2 modulo:2:2 abs:1:1 min:1:-1 max:1:-1 =:2:-1 <:2:-1 >:2:-1 <=:2:-1 >=:2:-1 zero?:1:1 even?:1:1 odd?:1:1")
	self.register("not:1:1 null?:1:1 pair?:1:1 list?:1:1 number?:1:1 string?:1:1 symbol?:1:1 boolean?:1:1 procedure?:1:1 eq?:2:2 equal?:2:2")
	self.register("cons:2:2 car:1:1 cdr:1:1 cadr:1:1 cddr:1:1 caddr:1:1 set-car!:2:2 set-cdr!:2:2 list:0:-1 length:1:1 append:0:-1 reverse:1:1 list-ref:2:2 list-tail:2:2 range:2:2 assoc:2:2 member:2:2")
	self.register("map:2:-1 for-each:2:-1 filter:2:2 fold:3:3 foldr:3:3 apply:2:-1 sort:2:2")
	self.register("string-length:1:1 string-append:0:-1 substring:3:3 string-ref:2:2 string=?:2:2 string<?:2:2 string-upcase:1:1 string-downcase:1:1 string->number:1:1 number->string:1:1 string->symbol:1:1 symbol->string:1:1 string->list:1:1 list->string:1:1 string-join:2:2 string-split:2:2 string-contains?:2:2")
	self.register("display:1:1 write:1:1 newline:0:0 void:0:0 error:1:-1")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var inp = stdin()
	data := read_all(inp)?
	var it = Interp()
	it.setup()
	it.src = data
	while true:
		it.skip_ws()
		if it.peek() == -1: break
		r := it.read_datum()
		if form := r:
			r2 := it.eval(form, 0)
			if r2.is_error():
				msg := r2.err().message
				if it.any_out and not it.last_nl: it.emit("\n")
				it.emit("error: {msg}\n")
				break
		else:
			msg := r.err().message
			if it.any_out and not it.last_nl: it.emit("\n")
			it.emit("error: {msg}\n")
			break
	it.flush()
