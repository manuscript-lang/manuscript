import wrapping_add, wrapping_multiply, wrapping_subtract from "@std/math/math.ms"
import stdin, stdout from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import read_all from "@std/io/streams.ms"

enum Value:
	VInt(n: Int)
	VBool(b: Bool)
	VStr(id: Int)
	VSym(id: Int)
	VNil
	VVoid
	VPair(id: Int)
	VClo(id: Int)
	VBuiltin(id: Int)

type Frame:
	names: List[Int]
	vals: List[Value]
	parent: Int

type Closure:
	params: List[Int]
	rest: Int
	body: List[Value]
	env: Int
	name: Int

type Params:
	names: List[Int]
	rest: Int

type Interp:
	syms: List[String] = []
	symmap: Map[String, Int] = Map[String, Int]()
	gidx: List[Int] = []
	strs: List[String] = []
	pcar: List[Value] = []
	pcdr: List[Value] = []
	frames: List[Frame] = []
	clos: List[Closure] = []
	bnames: List[String] = []
	bmin: List[Int] = []
	bmax: List[Int] = []
	depth: Int = 0
	out: List[String] = []
	out_any: Bool = false
	out_nl: Bool = true
	bs: Bytes = "".to_bytes()
	text: String = ""
	pos: Int = 0
	len: Int = 0

fn syn(msg: String) Error:
	return Error(msg, kind: "syntax")

fn is_syntax(e: Error) Bool:
	if k := e.kind:
		return k == "syntax"
	return false

fn min_int() Int: -9223372036854775807 - 1

fn add_ck(a: Int, b: Int) Int!:
	r := wrapping_add(a, b)
	if (a >= 0) == (b >= 0) and (r >= 0) != (a >= 0):
		return error(Error("integer overflow"))
	return ok(r)

fn sub_ck(a: Int, b: Int) Int!:
	r := wrapping_subtract(a, b)
	if (a >= 0) != (b >= 0) and (r >= 0) != (a >= 0):
		return error(Error("integer overflow"))
	return ok(r)

fn neg_ck(a: Int) Int!:
	if a == min_int():
		return error(Error("integer overflow"))
	return ok(0 - a)

fn mul_ck(a: Int, b: Int) Int!:
	if a == 0 or b == 0:
		return ok(0)
	if a == -1:
		return neg_ck(b)
	if b == -1:
		return neg_ck(a)
	r := wrapping_multiply(a, b)
	if r / a != b:
		return error(Error("integer overflow"))
	return ok(r)

fn is_delim(c: Int) Bool:
	return c == 32 or c == 9 or c == 10 or c == 13 or c == 40 or c == 41 or c == 34 or c == 59

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

fn Interp.sub(a: Int, b: Int) String:
	return self.text.slice(a, b).get("")

fn var Interp.intern(name: String) Int:
	if x := self.symmap.get(name):
		return x
	id := self.syms.length()
	self.syms.append(name.clone())
	self.symmap[name.clone()] = id
	self.gidx.append(-1)
	return id

fn var Interp.new_str(s: String) Value:
	id := self.strs.length()
	self.strs.append(s)
	return Value.VStr(id)

fn var Interp.cons(a: Value, b: Value) Value:
	id := self.pcar.length()
	self.pcar.append(a)
	self.pcdr.append(b)
	return Value.VPair(id)

fn var Interp.from_list(items: List[Value], tail: Value) Value:
	var r = tail
	var i = items.length() - 1
	while i >= 0:
		r = self.cons(items.get(i, Value.VNil), r)
		i -= 1
	return r

// Proper list to vector; none if improper.
fn Interp.to_vec(v: Value) List[Value]?:
	var items = List[Value]()
	var cur = v
	while true:
		match cur:
			VNil:
				return items
			VPair(p):
				items.append(self.pcar[p])
				cur = self.pcdr[p]
			_:
				return none
	return none

fn var Interp.define_in(env: Int, id: Int, v: Value) Unit:
	if env == 0:
		s := self.gidx[id]
		if s >= 0:
			self.frames[0].vals[s] = v
		else:
			self.gidx[id] = self.frames[0].vals.length()
			self.frames[0].names.append(id)
			self.frames[0].vals.append(v)
		return
	n := self.frames[env].names.length()
	for i in 0..n:
		if self.frames[env].names[i] == id:
			self.frames[env].vals[i] = v
			return
	self.frames[env].names.append(id)
	self.frames[env].vals.append(v)

fn Interp.slot(env: Int, id: Int) Int:
	if env == 0:
		return self.gidx[id]
	n := self.frames[env].names.length()
	for i in 0..n:
		if self.frames[env].names[i] == id:
			return i
	return -1

fn Interp.lookup(id: Int, env: Int) Value!:
	var e = env
	while e >= 0:
		s := self.slot(e, id)
		if s >= 0:
			return ok(self.frames[e].vals[s])
		e = self.frames[e].parent
	return error(Error("unbound variable: {self.syms[id]}"))

fn var Interp.new_frame(parent: Int) Int:
	self.frames.append(Frame(names: [], vals: [], parent: parent))
	return self.frames.length() - 1

fn var Interp.register(name: String, lo: Int, hi: Int) Unit:
	id := self.intern(name)
	b := self.bnames.length()
	self.bnames.append(name.clone())
	self.bmin.append(lo)
	self.bmax.append(hi)
	self.define_in(0, id, Value.VBuiltin(b))

// ---------- printing ----------

fn Interp.show(v: Value, w: Bool, var parts: List[String]) Unit:
	match v:
		VInt(n):
			parts.append("{n}")
		VBool(b):
			parts.append(if b: "#t" else: "#f")
		VStr(id):
			if w:
				s := self.strs[id].replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")
				parts.append("\"{s}\"")
			else:
				parts.append(self.strs[id].clone())
		VSym(id):
			parts.append(self.syms[id].clone())
		VNil:
			parts.append("()")
		VVoid:
			parts.append("#<void>")
		VClo(c):
			nm := self.clos[c].name
			if nm >= 0:
				parts.append("#<procedure {self.syms[nm]}>")
			else:
				parts.append("#<procedure>")
		VBuiltin(b):
			parts.append("#<builtin {self.bnames[b]}>")
		VPair(p):
			parts.append("(")
			self.show(self.pcar[p], w, var parts)
			var cur = self.pcdr[p]
			while true:
				match cur:
					VNil:
						break
					VPair(q):
						parts.append(" ")
						self.show(self.pcar[q], w, var parts)
						cur = self.pcdr[q]
					_:
						parts.append(" . ")
						self.show(cur, w, var parts)
						break
			parts.append(")")

fn Interp.fmt(v: Value, w: Bool) String:
	var parts = List[String]()
	self.show(v, w, var parts)
	return parts.join("")

fn var Interp.emit(s: String) Unit:
	if s.length() > 0:
		self.out_any = true
		self.out_nl = s.ends_with("\n")
		self.out.append(s)

fn Interp.terr(name: String, kind: String, v: Value) Error:
	return Error("{name}: expected {kind}, got {self.fmt(v, true)}")

// ---------- reader ----------

fn var Interp.skip_ws() Unit:
	while self.pos < self.len:
		c := self.bs.get(self.pos).to_int()
		if c == 32 or c == 9 or c == 10 or c == 13:
			self.pos += 1
		else if c == 59:
			while self.pos < self.len and self.bs.get(self.pos).to_int() != 10:
				self.pos += 1
		else:
			return

fn var Interp.read() Value!:
	self.skip_ws()
	if self.pos >= self.len:
		return error(syn("syntax error: unexpected end of input"))
	c := self.bs.get(self.pos).to_int()
	if c == 41:
		self.pos += 1
		return error(syn("syntax error: unexpected )"))
	if c == 40:
		self.pos += 1
		return self.read_list()
	if c == 39:
		self.pos += 1
		d := self.read()?
		return ok(self.from_list([Value.VSym(self.intern("quote")), d], Value.VNil))
	if c == 34:
		self.pos += 1
		return self.read_string()
	start := self.pos
	while self.pos < self.len and not is_delim(self.bs.get(self.pos).to_int()):
		self.pos += 1
	tok := self.sub(start, self.pos)
	if tok == "#t":
		return ok(Value.VBool(true))
	if tok == "#f":
		return ok(Value.VBool(false))
	if c == 35:
		return error(syn("syntax error: bad token: {tok}"))
	if tok == ".":
		return error(syn("syntax error: unexpected ."))
	var isnum = true
	var i = 0
	if c == 45:
		i = 1
	if i >= tok.length():
		isnum = false
	for j in i..tok.length():
		if not is_digit(tok.as_bytes().get(j).to_int()):
			isnum = false
			break
	if isnum:
		if n := tok.parse_int():
			return ok(Value.VInt(n))
		return error(syn("syntax error: integer out of range"))
	return ok(Value.VSym(self.intern(tok)))

fn var Interp.read_string() Value!:
	var parts = List[String]()
	var seg = self.pos
	while true:
		if self.pos >= self.len:
			return error(syn("syntax error: unterminated string"))
		c := self.bs.get(self.pos).to_int()
		if c == 34:
			parts.append(self.sub(seg, self.pos))
			self.pos += 1
			break
		if c == 92:
			parts.append(self.sub(seg, self.pos))
			self.pos += 1
			if self.pos >= self.len:
				return error(syn("syntax error: unterminated string"))
			e := self.bs.get(self.pos).to_int()
			if e == 110:
				parts.append("\n")
			else if e == 116:
				parts.append("\t")
			else if e == 92:
				parts.append("\\")
			else if e == 34:
				parts.append("\"")
			else:
				return error(syn("syntax error: bad escape"))
			self.pos += 1
			seg = self.pos
		else:
			self.pos += 1
	return ok(self.new_str(parts.join("")))

fn var Interp.read_list() Value!:
	var items = List[Value]()
	var tail = Value.VNil
	while true:
		self.skip_ws()
		if self.pos >= self.len:
			return error(syn("syntax error: unexpected end of input"))
		c := self.bs.get(self.pos).to_int()
		if c == 41:
			self.pos += 1
			break
		if c == 46 and (self.pos + 1 >= self.len or is_delim(self.bs.get(self.pos + 1).to_int())):
			if items.length() == 0:
				return error(syn("syntax error: bad dotted list"))
			self.pos += 1
			self.skip_ws()
			if self.pos >= self.len:
				return error(syn("syntax error: unexpected end of input"))
			if self.bs.get(self.pos).to_int() == 41:
				return error(syn("syntax error: bad dotted list"))
			tail = self.read()?
			self.skip_ws()
			if self.pos >= self.len:
				return error(syn("syntax error: unexpected end of input"))
			if self.bs.get(self.pos).to_int() != 41:
				return error(syn("syntax error: bad dotted list"))
			self.pos += 1
			break
		items.append(self.read()?)
	return ok(self.from_list(items, tail))

// ---------- evaluator ----------

fn bad(name: String) Error:
	return syn("syntax error: bad form: {name}")

fn truthy(v: Value) Bool:
	match v:
		VBool(b): return b
		_: return true

fn Interp.parse_params(v: Value) Params?:
	var names = List[Int]()
	var cur = v
	while true:
		match cur:
			VNil:
				return Params(names: names, rest: -1)
			VSym(id):
				if names.contains(id):
					return none
				return Params(names: names, rest: id)
			VPair(p):
				match self.pcar[p]:
					VSym(id):
						if names.contains(id):
							return none
						names.append(id)
					_:
						return none
				cur = self.pcdr[p]
			_:
				return none
	return none

fn var Interp.make_closure(ps: Params, body: List[Value], env: Int, name: Int) Value:
	self.clos.append(Closure(params: ps.names.clone(), rest: ps.rest, body: body.clone(), env: env, name: name))
	return Value.VClo(self.clos.length() - 1)

fn Interp.arity_err(name: String, expected: String, got: Int) Error:
	return Error("wrong number of arguments to {name}: expected {expected}, got {got}")

// Bind closure params into a new frame.
fn var Interp.bind_call(c: Int, args: List[Value]) Int!:
	np := self.clos[c].params.length()
	rest := self.clos[c].rest
	if args.length() < np or (rest < 0 and args.length() > np):
		nm := self.clos[c].name
		name := if nm >= 0: self.syms[nm].clone() else: "lambda"
		exp := if rest >= 0: "at least {np}" else: "{np}"
		return error(self.arity_err(name, exp, args.length()))
	f := self.new_frame(self.clos[c].env)
	for i in 0..np:
		self.frames[f].names.append(self.clos[c].params[i])
		self.frames[f].vals.append(args[i])
	if rest >= 0:
		var tail = Value.VNil
		var i = args.length() - 1
		while i >= np:
			tail = self.cons(args[i], tail)
			i -= 1
		self.frames[f].names.append(rest)
		self.frames[f].vals.append(tail)
	return ok(f)

fn var Interp.eval(e: Value, env: Int) Value!:
	saved := self.depth
	r := self.eval_inner(e, env)
	self.depth = saved
	return r

fn var Interp.enter(counted: Bool) Unit!:
	if not counted:
		self.depth += 1
		if self.depth > 10000:
			return error(Error("recursion limit exceeded"))
	return ok(unit)

fn var Interp.eval_seq(items: List[Value], from: Int, env: Int) Unit!:
	for i in from..items.length():
		_v := self.eval(items[i], env)?
	return ok(unit)

fn var Interp.apply(f: Value, args: List[Value]) Value!:
	match f:
		VClo(c):
			saved := self.depth
			self.depth += 1
			if self.depth > 10000:
				self.depth = saved
				return error(Error("recursion limit exceeded"))
			fr := self.bind_call(c, args)?
			n := self.clos[c].body.length()
			var res = Value.VVoid
			for i in 0..n:
				res = self.eval(self.clos[c].body[i], fr)?
			self.depth = saved
			return ok(res)
		VBuiltin(b):
			return self.call_builtin(b, args)
		_:
			return error(Error("not a procedure: {self.fmt(f, true)}"))

fn var Interp.eval_inner(e0: Value, env0: Int) Value!:
	var expr = e0
	var env = env0
	var counted = false
	while true:
		match expr:
			VSym(id):
				return self.lookup(id, env)
			VNil:
				return error(syn("syntax error: empty application"))
			VPair(p):
				head := self.pcar[p]
				rest_v := self.pcdr[p]
				var sid = -1
				match head:
					VSym(id):
						sid = id
					_:
						sid = -1
				if sid >= 0 and sid < 15:
					args := self.to_vec(rest_v).ok_or(bad(self.syms[sid].clone()))?
					na := args.length()
					nm := self.syms[sid].clone()
					if sid == 0:
						if na != 1:
							return error(bad(nm))
						return ok(args[0])
					if sid == 1:
						if na < 2 or na > 3:
							return error(bad(nm))
						t := self.eval(args[0], env)?
						if truthy(t):
							expr = args[1]
							continue
						if na == 3:
							expr = args[2]
							continue
						return ok(Value.VVoid)
					if sid == 2:
						if na < 2:
							return error(bad(nm))
						match args[0]:
							VSym(name):
								if na != 2:
									return error(bad(nm))
								v := self.eval(args[1], env)?
								match v:
									VClo(c):
										if self.clos[c].name < 0 and self.is_lambda_form(args[1]):
											self.clos[c].name = name
									_:
										unit
								self.define_in(env, name, v)
								return ok(Value.VVoid)
							VPair(hp):
								match self.pcar[hp]:
									VSym(name):
										ps := self.parse_params(self.pcdr[hp]).ok_or(bad(nm))?
										body := args.slice(1, na)?
										v := self.make_closure(ps, body, env, name)
										self.define_in(env, name, v)
										return ok(Value.VVoid)
									_:
										return error(bad(nm))
							_:
								return error(bad(nm))
					if sid == 3:
						if na != 2:
							return error(bad(nm))
						match args[0]:
							VSym(name):
								v := self.eval(args[1], env)?
								var fe = env
								while fe >= 0:
									if self.slot(fe, name) >= 0:
										break
									fe = self.frames[fe].parent
								if fe < 0:
									return error(Error("unbound variable: {self.syms[name]}"))
								s := self.slot(fe, name)
								self.frames[fe].vals[s] = v
								return ok(Value.VVoid)
							_:
								return error(bad(nm))
					if sid == 4:
						if na < 2:
							return error(bad(nm))
						ps := self.parse_params(args[0]).ok_or(bad(nm))?
						body := args.slice(1, na)?
						return ok(self.make_closure(ps, body, env, -1))
					if sid == 5:
						if na == 0:
							return ok(Value.VVoid)
						self.eval_seq(args, 0, env)?
						expr = args[na - 1]
						continue
					if sid == 6 or sid == 7 or sid == 8:
						var named = -1
						var bi = 0
						if na >= 1:
							match args[0]:
								VSym(nn):
									named = nn
									bi = 1
								_:
									unit
						if named >= 0 and sid != 6:
							return error(bad(nm))
						if na < bi + 2:
							return error(bad(nm))
						binds := self.to_vec(args[bi]).ok_or(bad(nm))?
						var bnames = List[Int]()
						var binits = List[Value]()
						for b in binds:
							bv := self.to_vec(b).ok_or(bad(nm))?
							if bv.length() != 2:
								return error(bad(nm))
							match bv[0]:
								VSym(x):
									bnames.append(x)
								_:
									return error(bad(nm))
							binits.append(bv[1])
						body := args.slice(bi + 1, na)?
						if named >= 0:
							var vals = List[Value]()
							for ini in binits:
								vals.append(self.eval(ini, env)?)
							f1 := self.new_frame(env)
							ps := Params(names: bnames, rest: -1)
							cl := self.make_closure(ps, body, f1, named)
							self.define_in(f1, named, cl)
							match cl:
								VClo(c):
									self.enter(counted)?
									counted = true
									env = self.bind_call(c, vals)?
								_:
									unit
							self.eval_seq(body, 0, env)?
							expr = body[body.length() - 1]
							continue
						if sid == 6:
							var vals = List[Value]()
							for ini in binits:
								vals.append(self.eval(ini, env)?)
							f := self.new_frame(env)
							for i in 0..bnames.length():
								self.define_in(f, bnames[i], vals[i])
							env = f
						else:
							f := self.new_frame(env)
							for i in 0..bnames.length():
								v := self.eval(binits[i], f)?
								self.define_in(f, bnames[i], v)
							env = f
						// body: all but last, then tail
						for i in 0..body.length() - 1:
							_v := self.eval(body[i], env)?
						expr = body[body.length() - 1]
						continue
					if sid == 9:
						var cur = rest_v
						var matched = false
						while true:
							match cur:
								VNil:
									break
								VPair(cp):
									clause := self.to_vec(self.pcar[cp]).ok_or(bad(nm))?
									if clause.length() == 0:
										return error(bad(nm))
									isl := self.is_else(clause[0])
									if isl:
										if clause.length() < 2:
											return error(bad(nm))
										match self.pcdr[cp]:
											VNil:
												unit
											_:
												return error(bad(nm))
										for i in 1..clause.length() - 1:
											_v := self.eval(clause[i], env)?
										expr = clause[clause.length() - 1]
										matched = true
										break
									t := self.eval(clause[0], env)?
									if truthy(t):
										if clause.length() == 1:
											return ok(t)
										for i in 1..clause.length() - 1:
											_v := self.eval(clause[i], env)?
										expr = clause[clause.length() - 1]
										matched = true
										break
									cur = self.pcdr[cp]
								_:
									return error(bad(nm))
						if matched:
							continue
						return ok(Value.VVoid)
					if sid == 10:
						if na == 0:
							return ok(Value.VBool(true))
						for i in 0..na - 1:
							t := self.eval(args[i], env)?
							if not truthy(t):
								return ok(t)
						expr = args[na - 1]
						continue
					if sid == 11:
						if na == 0:
							return ok(Value.VBool(false))
						for i in 0..na - 1:
							t := self.eval(args[i], env)?
							if truthy(t):
								return ok(t)
						expr = args[na - 1]
						continue
					if sid == 12 or sid == 13:
						if na < 2:
							return error(bad(nm))
						t := truthy(self.eval(args[0], env)?)
						if t == (sid == 12):
							for i in 1..na - 1:
								_v := self.eval(args[i], env)?
							expr = args[na - 1]
							continue
						return ok(Value.VVoid)
					if sid == 14:
						if na != 2:
							return error(bad(nm))
						r := self.eval(args[0], env)
						if v := r:
							return ok(v)
						er := r.err()
						if is_syntax(er):
							return error(er)
						h := self.eval(args[1], env)?
						msg := self.new_str(er.message.clone())
						return self.apply(h, [msg])
				// application
				items := self.to_vec(expr).ok_or(syn("syntax error: bad application"))?
				f := self.eval(items[0], env)?
				var argv = List[Value]()
				for i in 1..items.length():
					argv.append(self.eval(items[i], env)?)
				match f:
					VClo(c):
						self.enter(counted)?
						counted = true
						env = self.bind_call(c, argv)?
						n := self.clos[c].body.length()
						for i in 0..n - 1:
							_v := self.eval(self.clos[c].body[i], env)?
						expr = self.clos[c].body[n - 1]
						continue
					VBuiltin(b):
						return self.call_builtin(b, argv)
					_:
						return error(Error("not a procedure: {self.fmt(f, true)}"))
			_:
				return ok(expr)
	return ok(Value.VVoid)

fn Interp.is_sym(v: Value, id: Int) Bool:
	match v:
		VSym(x): return x == id
		_: return false

fn Interp.is_else(v: Value) Bool:
	match v:
		VSym(x): return self.syms[x] == "else"
		_: return false

fn Interp.is_lambda_form(v: Value) Bool:
	match v:
		VPair(p): return self.is_sym(self.pcar[p], 4)
		_: return false

// ---------- builtins ----------

fn Interp.int_arg(name: String, v: Value) Int!:
	match v:
		VInt(n): return ok(n)
		_: return error(self.terr(name, "integer", v))

fn Interp.str_arg(name: String, v: Value) String!:
	match v:
		VStr(id): return ok(self.strs[id].clone())
		_: return error(self.terr(name, "string", v))

fn Interp.list_arg(name: String, v: Value) List[Value]!:
	if items := self.to_vec(v):
		return ok(items)
	return error(self.terr(name, "list", v))

fn Interp.proc_arg(name: String, v: Value) Unit!:
	match v:
		VClo(_): return ok(unit)
		VBuiltin(_): return ok(unit)
		_: return error(self.terr(name, "procedure", v))

fn Interp.equal(a: Value, b: Value) Bool:
	match a:
		VInt(x):
			match b:
				VInt(y): return x == y
				_: return false
		VBool(x):
			match b:
				VBool(y): return x == y
				_: return false
		VStr(x):
			match b:
				VStr(y): return self.strs[x] == self.strs[y]
				_: return false
		VSym(x):
			match b:
				VSym(y): return x == y
				_: return false
		VNil:
			match b:
				VNil: return true
				_: return false
		VVoid:
			match b:
				VVoid: return true
				_: return false
		VClo(x):
			match b:
				VClo(y): return x == y
				_: return false
		VBuiltin(x):
			match b:
				VBuiltin(y): return x == y
				_: return false
		VPair(x):
			match b:
				VPair(y):
					if x == y:
						return true
					return self.equal(self.pcar[x], self.pcar[y]) and self.equal(self.pcdr[x], self.pcdr[y])
				_: return false

fn Interp.eqp(a: Value, b: Value) Bool:
	match a:
		VInt(_): return self.equal(a, b)
		VBool(_): return self.equal(a, b)
		VSym(_): return self.equal(a, b)
		VNil: return self.equal(a, b)
		_: return false

fn var Interp.merge_sort(items: List[Value], less: Value) List[Value]!:
	n := items.length()
	if n <= 1:
		return ok(items.clone())
	mid := n / 2
	left := self.merge_sort(items.slice(0, mid)?, less)?
	right := self.merge_sort(items.slice(mid, n)?, less)?
	var res = List[Value]()
	var i = 0
	var j = 0
	while i < left.length() and j < right.length():
		r := self.apply(less, [right[j], left[i]])?
		if truthy(r):
			res.append(right[j])
			j += 1
		else:
			res.append(left[i])
			i += 1
	while i < left.length():
		res.append(left[i])
		i += 1
	while j < right.length():
		res.append(right[j])
		j += 1
	return ok(res)

fn Interp.cxr(name: String, path: String, v: Value) Value!:
	var cur = v
	var i = path.length() - 1
	while i >= 0:
		match cur:
			VPair(p):
				if path.slice(i, i + 1).get("") == "a":
					cur = self.pcar[p]
				else:
					cur = self.pcdr[p]
			_:
				return error(self.terr(name, "pair", cur))
		i -= 1
	return ok(cur)

fn var Interp.call_builtin(b: Int, args: List[Value]) Value!:
	name := self.bnames[b].clone()
	n := args.length()
	lo := self.bmin[b]
	hi := self.bmax[b]
	if n < lo or (hi >= 0 and n > hi):
		exp := if hi < 0: "at least {lo}" else if lo == hi: "{lo}" else: "{lo} to {hi}"
		return error(self.arity_err(name, exp, n))
	var key = name.clone()
	if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
		key = "cmp"
	if name == "quotient" or name == "remainder" or name == "modulo":
		key = "div"
	if name == "min" or name == "max":
		key = "minmax"
	if name == "car" or name == "cdr":
		key = "carcdr"
	if name == "set-car!" or name == "set-cdr!":
		key = "setcar"
	if name == "assoc" or name == "member":
		key = "assoc"
	if name == "string=?" or name == "string<?":
		key = "strcmp"
	match key:
		"+":
			var acc = 0
			for a in args:
				acc = add_ck(acc, self.int_arg(name, a)?)?
			return ok(Value.VInt(acc))
		"-":
			first := self.int_arg(name, args[0])?
			if n == 1:
				return ok(Value.VInt(neg_ck(first)?))
			var acc = first
			for i in 1..n:
				acc = sub_ck(acc, self.int_arg(name, args[i])?)?
			return ok(Value.VInt(acc))
		"*":
			var acc = 1
			for a in args:
				acc = mul_ck(acc, self.int_arg(name, a)?)?
			return ok(Value.VInt(acc))
		"cmp":
			var nums = List[Int]()
			for a in args:
				nums.append(self.int_arg(name, a)?)
			for i in 0..n - 1:
				x := nums[i]
				y := nums[i + 1]
				okc := if name == "=": x == y else if name == "<": x < y else if name == ">": x > y else if name == "<=": x <= y else: x >= y
				if not okc:
					return ok(Value.VBool(false))
			return ok(Value.VBool(true))
		"div":
			x := self.int_arg(name, args[0])?
			y := self.int_arg(name, args[1])?
			if y == 0:
				return error(Error("division by zero"))
			if name == "quotient":
				if x == min_int() and y == -1:
					return error(Error("integer overflow"))
				return ok(Value.VInt(x / y))
			if y == -1:
				return ok(Value.VInt(0))
			var r = x % y
			if name == "modulo" and r != 0 and (r < 0) != (y < 0):
				r += y
			return ok(Value.VInt(r))
		"abs":
			x := self.int_arg(name, args[0])?
			if x < 0:
				return ok(Value.VInt(neg_ck(x)?))
			return ok(Value.VInt(x))
		"minmax":
			var acc = self.int_arg(name, args[0])?
			for i in 1..n:
				x := self.int_arg(name, args[i])?
				if name == "min":
					if x < acc:
						acc = x
				else:
					if x > acc:
						acc = x
			return ok(Value.VInt(acc))
		"zero?":
			return ok(Value.VBool(self.int_arg(name, args[0])? == 0))
		"even?":
			return ok(Value.VBool(self.int_arg(name, args[0])? % 2 == 0))
		"odd?":
			return ok(Value.VBool(self.int_arg(name, args[0])? % 2 != 0))
		"not":
			return ok(Value.VBool(not truthy(args[0])))
		"null?":
			match args[0]:
				VNil: return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"pair?":
			match args[0]:
				VPair(_): return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"list?":
			return ok(Value.VBool(self.to_vec(args[0]).is_some()))
		"number?":
			match args[0]:
				VInt(_): return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"string?":
			match args[0]:
				VStr(_): return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"symbol?":
			match args[0]:
				VSym(_): return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"boolean?":
			match args[0]:
				VBool(_): return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"procedure?":
			match args[0]:
				VClo(_): return ok(Value.VBool(true))
				VBuiltin(_): return ok(Value.VBool(true))
				_: return ok(Value.VBool(false))
		"eq?":
			return ok(Value.VBool(self.eqp(args[0], args[1])))
		"equal?":
			return ok(Value.VBool(self.equal(args[0], args[1])))
		"cons":
			return ok(self.cons(args[0], args[1]))
		"carcdr":
			match args[0]:
				VPair(p):
					return ok(if name == "car": self.pcar[p] else: self.pcdr[p])
				_:
					return error(self.terr(name, "pair", args[0]))
		"cadr":
			return self.cxr(name, "ad", args[0])
		"cddr":
			return self.cxr(name, "dd", args[0])
		"caddr":
			return self.cxr(name, "add", args[0])
		"setcar":
			match args[0]:
				VPair(p):
					if name == "set-car!":
						self.pcar[p] = args[1]
					else:
						self.pcdr[p] = args[1]
					return ok(Value.VVoid)
				_:
					return error(self.terr(name, "pair", args[0]))
		"list":
			return ok(self.from_list(args, Value.VNil))
		"length":
			items := self.list_arg(name, args[0])?
			return ok(Value.VInt(items.length()))
		"append":
			if n == 0:
				return ok(Value.VNil)
			var all = List[Value]()
			for i in 0..n - 1:
				items := self.list_arg(name, args[i])?
				for x in items:
					all.append(x)
			return ok(self.from_list(all, args[n - 1]))
		"reverse":
			items := self.list_arg(name, args[0])?
			var r = Value.VNil
			for x in items:
				r = self.cons(x, r)
			return ok(r)
		"list-ref":
			items := self.list_arg(name, args[0])?
			i := self.int_arg(name, args[1])?
			if i < 0 or i >= items.length():
				return error(Error("list-ref: index out of range"))
			return ok(items[i])
		"list-tail":
			items := self.list_arg(name, args[0])?
			i := self.int_arg(name, args[1])?
			if i < 0 or i > items.length():
				return error(Error("list-tail: index out of range"))
			var cur = args[0]
			for _k in 0..i:
				match cur:
					VPair(p): cur = self.pcdr[p]
					_: unit
			return ok(cur)
		"range":
			a := self.int_arg(name, args[0])?
			c := self.int_arg(name, args[1])?
			var items = List[Value]()
			var i = a
			while i < c:
				items.append(Value.VInt(i))
				i += 1
			return ok(self.from_list(items, Value.VNil))
		"assoc":
			items := self.list_arg(name, args[1])?
			var cur = args[1]
			for x in items:
				if name == "assoc":
					match x:
						VPair(p):
							if self.equal(self.pcar[p], args[0]):
								return ok(x)
						_:
							return error(self.terr(name, "pair", x))
				else:
					if self.equal(x, args[0]):
						return ok(cur)
					match cur:
						VPair(p): cur = self.pcdr[p]
						_: unit
			return ok(Value.VBool(false))
		"map":
			self.proc_arg(name, args[0])?
			var lists = List[List[Value]]()
			for i in 1..n:
				lists.append(self.list_arg(name, args[i])?)
			var m = lists[0].length()
			for l in lists:
				if l.length() < m:
					m = l.length()
			var res = List[Value]()
			for k in 0..m:
				var call = List[Value]()
				for l in lists:
					call.append(l[k])
				res.append(self.apply(args[0], call)?)
			return ok(self.from_list(res, Value.VNil))
		"for-each":
			self.proc_arg(name, args[0])?
			var lists = List[List[Value]]()
			for i in 1..n:
				lists.append(self.list_arg(name, args[i])?)
			var m = lists[0].length()
			for l in lists:
				if l.length() < m:
					m = l.length()
			for k in 0..m:
				var call = List[Value]()
				for l in lists:
					call.append(l[k])
				_v := self.apply(args[0], call)?
			return ok(Value.VVoid)
		"filter":
			self.proc_arg(name, args[0])?
			items := self.list_arg(name, args[1])?
			var res = List[Value]()
			for x in items:
				if truthy(self.apply(args[0], [x])?):
					res.append(x)
			return ok(self.from_list(res, Value.VNil))
		"fold":
			self.proc_arg(name, args[0])?
			items := self.list_arg(name, args[2])?
			var acc = args[1]
			for x in items:
				acc = self.apply(args[0], [acc, x])?
			return ok(acc)
		"foldr":
			self.proc_arg(name, args[0])?
			items := self.list_arg(name, args[2])?
			var acc = args[1]
			var i = items.length() - 1
			while i >= 0:
				acc = self.apply(args[0], [items[i], acc])?
				i -= 1
			return ok(acc)
		"apply":
			self.proc_arg(name, args[0])?
			last := self.list_arg(name, args[n - 1])?
			var call = List[Value]()
			for i in 1..n - 1:
				call.append(args[i])
			for x in last:
				call.append(x)
			return self.apply(args[0], call)
		"sort":
			self.proc_arg(name, args[1])?
			items := self.list_arg(name, args[0])?
			sorted := self.merge_sort(items, args[1])?
			return ok(self.from_list(sorted, Value.VNil))
		"string-length":
			s := self.str_arg(name, args[0])?
			return ok(Value.VInt(s.length()))
		"string-append":
			var sb = List[String]()
			for a in args:
				sb.append(self.str_arg(name, a)?)
			return ok(self.new_str(sb.join("")))
		"substring":
			s := self.str_arg(name, args[0])?
			a := self.int_arg(name, args[1])?
			c := self.int_arg(name, args[2])?
			if a < 0 or a > c or c > s.length():
				return error(Error("substring: index out of range"))
			return ok(self.new_str(s.slice(a, c).get("")))
		"string-ref":
			s := self.str_arg(name, args[0])?
			i := self.int_arg(name, args[1])?
			if i < 0 or i >= s.length():
				return error(Error("string-ref: index out of range"))
			return ok(self.new_str(s.slice(i, i + 1).get("")))
		"strcmp":
			x := self.str_arg(name, args[0])?
			y := self.str_arg(name, args[1])?
			if name == "string=?":
				return ok(Value.VBool(x == y))
			return ok(Value.VBool(x.compare(y) < 0))
		"string-upcase":
			s := self.str_arg(name, args[0])?
			return ok(self.new_str(s.upper()))
		"string-downcase":
			s := self.str_arg(name, args[0])?
			return ok(self.new_str(s.lower()))
		"string->number":
			s := self.str_arg(name, args[0])?
			if s.starts_with("+"):
				return ok(Value.VBool(false))
			if v := s.parse_int():
				return ok(Value.VInt(v))
			return ok(Value.VBool(false))
		"number->string":
			x := self.int_arg(name, args[0])?
			return ok(self.new_str("{x}"))
		"string->symbol":
			s := self.str_arg(name, args[0])?
			return ok(Value.VSym(self.intern(s)))
		"symbol->string":
			match args[0]:
				VSym(id): return ok(self.new_str(self.syms[id].clone()))
				_: return error(self.terr(name, "symbol", args[0]))
		"string->list":
			s := self.str_arg(name, args[0])?
			var items = List[Value]()
			for i in 0..s.length():
				items.append(self.new_str(s.slice(i, i + 1).get("")))
			return ok(self.from_list(items, Value.VNil))
		"list->string":
			items := self.list_arg(name, args[0])?
			var sb = List[String]()
			for x in items:
				sb.append(self.str_arg(name, x)?)
			return ok(self.new_str(sb.join("")))
		"string-join":
			items := self.list_arg(name, args[0])?
			sep := self.str_arg(name, args[1])?
			var sb = List[String]()
			for x in items:
				sb.append(self.str_arg(name, x)?)
			return ok(self.new_str(sb.join(sep)))
		"string-split":
			s := self.str_arg(name, args[0])?
			sep := self.str_arg(name, args[1])?
			if sep.length() != 1:
				return error(Error("string-split: separator must be one character"))
			var items = List[Value]()
			for part in s.split(sep):
				items.append(self.new_str(part.clone()))
			return ok(self.from_list(items, Value.VNil))
		"string-contains?":
			s := self.str_arg(name, args[0])?
			sub := self.str_arg(name, args[1])?
			return ok(Value.VBool(s.contains(sub)))
		"display":
			self.emit(self.fmt(args[0], false))
			return ok(Value.VVoid)
		"write":
			self.emit(self.fmt(args[0], true))
			return ok(Value.VVoid)
		"newline":
			self.emit("\n")
			return ok(Value.VVoid)
		"void":
			return ok(Value.VVoid)
		"error":
			msg := self.str_arg(name, args[0])?
			var parts = List[String]()
			parts.append(msg)
			for i in 1..n:
				parts.append(" ")
				parts.append(self.fmt(args[i], true))
			return error(Error(parts.join("")))
		_:
			return error(Error("unknown builtin {name}"))

fn var Interp.setup() Unit:
	for k in ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try"]:
		self.intern(k)
	self.frames.append(Frame(names: [], vals: [], parent: -1))
	regs := [
		"+:0:-1", "-:1:-1", "*:0:-1", "quotient:2:2", "remainder:2:2", "modulo:2:2", "abs:1:1",
		"min:1:-1", "max:1:-1", "=:2:-1", "<:2:-1", ">:2:-1", "<=:2:-1", ">=:2:-1",
		"zero?:1:1", "even?:1:1", "odd?:1:1", "not:1:1", "null?:1:1", "pair?:1:1", "list?:1:1",
		"number?:1:1", "string?:1:1", "symbol?:1:1", "boolean?:1:1", "procedure?:1:1",
		"eq?:2:2", "equal?:2:2", "cons:2:2", "car:1:1", "cdr:1:1", "cadr:1:1", "cddr:1:1", "caddr:1:1",
		"set-car!:2:2", "set-cdr!:2:2", "list:0:-1", "length:1:1", "append:0:-1", "reverse:1:1",
		"list-ref:2:2", "list-tail:2:2", "range:2:2", "assoc:2:2", "member:2:2",
		"map:2:-1", "for-each:2:-1", "filter:2:2", "fold:3:3", "foldr:3:3", "apply:2:-1", "sort:2:2",
		"string-length:1:1", "string-append:0:-1", "substring:3:3", "string-ref:2:2", "string=?:2:2",
		"string<?:2:2", "string-upcase:1:1", "string-downcase:1:1", "string->number:1:1",
		"number->string:1:1", "string->symbol:1:1", "symbol->string:1:1", "string->list:1:1",
		"list->string:1:1", "string-join:2:2", "string-split:2:2", "string-contains?:2:2",
		"display:1:1", "write:1:1", "newline:0:0", "void:0:0", "error:1:-1"
	]
	for r in regs:
		parts := r.split(":")
		// names like "string->list" contain no colon; the first part is the name
		nm := parts[0].clone()
		lo := parts[1].parse_int().get(0)
		hi := parts[2].parse_int().get(0)
		self.register(nm, lo, hi)

// ---------- main ----------

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	var it = Interp()
	it.text = data.decode_utf8().get("")
	it.bs = it.text.to_bytes()
	it.len = it.bs.length()
	it.setup()
	while true:
		it.skip_ws()
		if it.pos >= it.len:
			break
		form := it.read()
		if f := form:
			r := it.eval(f, 0)
			if r.is_error():
				m := r.err().message.clone()
				if it.out_any and not it.out_nl:
					it.emit("\n")
				it.emit("error: {m}\n")
				break
		else:
			m := form.err().message.clone()
			if it.out_any and not it.out_nl:
				it.emit("\n")
			it.emit("error: {m}\n")
			break
	var o = stdout()
	o.write(it.out.join(""))?
	o.flush()?
