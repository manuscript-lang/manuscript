import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import wrapping_multiply from "@std/math/math.ms"

enum Val:
	Num(n: Int)
	Boolean(b: Bool)
	Str(id: Int)
	Sym(id: Int)
	Nil
	Pair(id: Int)
	Clo(id: Int)
	Prim(id: Int)
	Void
	Unbound
	Dot

type Closure:
	params: List[Int]
	rest: Int
	body: Val
	env: Int
	name: Int

type Frame:
	names: List[Int]
	vals: List[Val]
	parent: Int

type Interp:
	src: String = ""
	pos: Int = 0
	strs: List[String] = List[String]()
	symnames: List[String] = List[String]()
	symmap: Map[String, Int] = Map[String, Int]()
	globals: List[Val] = List[Val]()
	cars: List[Val] = List[Val]()
	cdrs: List[Val] = List[Val]()
	closures: List[Closure] = List[Closure]()
	frames: List[Frame] = List[Frame]()
	pnames: List[String] = List[String]()
	pmin: List[Int] = List[Int]()
	pmax: List[Int] = List[Int]()
	depth: Int = 0
	out: String = ""
	any_out: Bool = false
	last_nl: Bool = true

fn min_int() Int: -9223372036854775807 - 1
fn max_int() Int: 9223372036854775807

fn is_syntax(e: Error) Bool:
	if k := e.kind:
		return k == "syntax"
	return false

fn syn(msg: String) Error:
	return Error(msg, kind: "syntax")

fn rt(msg: String) Error:
	return Error(msg)

fn is_dot(v: Val) Bool:
	match v:
		Dot: return true
		_: return false

fn is_false(v: Val) Bool:
	match v:
		Boolean(b): return not b
		_: return false

fn sym_id(v: Val) Int:
	match v:
		Sym(id): return id
		_: return -1

fn is_delim(c: Int) Bool:
	return c == 32 or c == 9 or c == 10 or c == 13 or c == 40 or c == 41 or c == 34 or c == 59

fn is_int_tok(t: String) Bool:
	n := t.length()
	var start = 0
	if n > 0 and t.scalar_at(0) == 45:
		start = 1
	if start >= n: return false
	for i in start..n:
		c := t.scalar_at(i)
		if c < 48 or c > 57: return false
	return true

fn parse_digits(t: String) Int?:
	n := t.length()
	var neg = false
	var start = 0
	if t.scalar_at(0) == 45:
		neg = true
		start = 1
	var acc = 0
	minv := min_int()
	for i in start..n:
		d := t.scalar_at(i) - 48
		if acc < (minv + d) / 10: return none
		acc = acc * 10 - d
	if neg: return acc
	if acc == minv: return none
	return -acc

fn arity_text(lo: Int, hi: Int) String:
	if hi < 0: return "at least {lo}"
	if lo == hi: return "{lo}"
	return "{lo} to {hi}"

fn var Interp.intern_sym(name: String) Int:
	if id := self.symmap.get(name):
		return id
	id := self.symnames.length()
	self.symnames.append(name.clone())
	self.symmap[name.clone()] = id
	self.globals.append(Val.Unbound)
	return id

fn var Interp.mkstr(s: String) Val:
	self.strs.append(s)
	return Val.Str(self.strs.length() - 1)

fn var Interp.cons(a: Val, d: Val) Val:
	self.cars.append(a)
	self.cdrs.append(d)
	return Val.Pair(self.cars.length() - 1)

fn var Interp.mklist(items: List[Val], tail: Val) Val:
	var r = tail
	var i = items.length() - 1
	while i >= 0:
		r = self.cons(items[i], r)
		i -= 1
	return r

fn Interp.cdr_of(v: Val) Val:
	match v:
		Pair(p): return self.cdrs[p]
		_: return Val.Nil

fn Interp.car_of(v: Val) Val:
	match v:
		Pair(p): return self.cars[p]
		_: return Val.Nil

fn Interp.to_vec(v: Val) List[Val]?:
	var out = List[Val]()
	var cur = v
	while true:
		match cur:
			Nil: return out
			Pair(p):
				out.append(self.cars[p])
				cur = self.cdrs[p]
			_: return none
	return none

// ---------------- reader ----------------

fn var Interp.skip_ws() Unit:
	n := self.src.length()
	while self.pos < n:
		c := self.src.scalar_at(self.pos)
		if c == 32 or c == 9 or c == 10 or c == 13:
			self.pos += 1
		else if c == 59:
			while self.pos < n and self.src.scalar_at(self.pos) != 10:
				self.pos += 1
		else:
			break

fn var Interp.read_datum() Val!:
	self.skip_ws()
	n := self.src.length()
	if self.pos >= n: return error(syn("syntax error: unexpected end of input"))
	c := self.src.scalar_at(self.pos)
	if c == 41:
		self.pos += 1
		return error(syn("syntax error: unexpected )"))
	if c == 40:
		self.pos += 1
		return self.read_list()
	if c == 39:
		self.pos += 1
		d := self.read_datum()?
		if is_dot(d): return error(syn("syntax error: unexpected ."))
		q := Val.Sym(self.intern_sym("quote"))
		inner := self.cons(d, Val.Nil)
		return ok(self.cons(q, inner))
	if c == 34:
		return self.read_string()
	return self.read_atom()

fn var Interp.read_list() Val!:
	var items = List[Val]()
	var tail = Val.Nil
	n := self.src.length()
	while true:
		self.skip_ws()
		if self.pos >= n: return error(syn("syntax error: unexpected end of input"))
		c := self.src.scalar_at(self.pos)
		if c == 41:
			self.pos += 1
			break
		d := self.read_datum()?
		if is_dot(d):
			if items.length() == 0: return error(syn("syntax error: bad dotted list"))
			self.skip_ws()
			if self.pos >= n: return error(syn("syntax error: unexpected end of input"))
			if self.src.scalar_at(self.pos) == 41: return error(syn("syntax error: bad dotted list"))
			t := self.read_datum()?
			if is_dot(t): return error(syn("syntax error: unexpected ."))
			self.skip_ws()
			if self.pos >= n: return error(syn("syntax error: unexpected end of input"))
			if self.src.scalar_at(self.pos) != 41: return error(syn("syntax error: bad dotted list"))
			self.pos += 1
			tail = t
			break
		items.append(d)
	return ok(self.mklist(items, tail))

fn var Interp.read_string() Val!:
	n := self.src.length()
	self.pos += 1
	var s = ""
	while true:
		if self.pos >= n: return error(syn("syntax error: unterminated string"))
		c := self.src.scalar_at(self.pos)
		if c == 34:
			self.pos += 1
			break
		if c == 92:
			if self.pos + 1 >= n: return error(syn("syntax error: unterminated string"))
			e := self.src.scalar_at(self.pos + 1)
			if e == 110: s += "\n"
			else if e == 116: s += "\t"
			else if e == 92: s += "\\"
			else if e == 34: s += "\""
			else: return error(syn("syntax error: bad escape"))
			self.pos += 2
		else:
			s += self.src.view(self.pos, self.pos + 1)
			self.pos += 1
	return ok(self.mkstr(s))

fn var Interp.read_atom() Val!:
	n := self.src.length()
	start := self.pos
	while self.pos < n and not is_delim(self.src.scalar_at(self.pos)):
		self.pos += 1
	tok := self.src.view(start, self.pos).clone()
	if tok == "#t": return ok(Val.Boolean(true))
	if tok == "#f": return ok(Val.Boolean(false))
	if tok.scalar_at(0) == 35: return error(syn("syntax error: bad token: {tok}"))
	if is_int_tok(tok):
		if v := parse_digits(tok):
			return ok(Val.Num(v))
		return error(syn("syntax error: integer out of range"))
	if tok == ".": return ok(Val.Dot)
	return ok(Val.Sym(self.intern_sym(tok)))

// ---------------- printing ----------------

fn var Interp.show(v: Val, w: Bool) String:
	match v:
		Num(n): return "{n}"
		Boolean(b):
			if b: return "#t"
			return "#f"
		Str(id):
			if not w: return self.strs[id].clone()
			t := self.strs[id].replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")
			return "\"" + t + "\""
		Sym(id): return self.symnames[id].clone()
		Nil: return "()"
		Void: return "#<void>"
		Clo(id):
			nm := self.closures[id].name
			if nm < 0: return "#<procedure>"
			return "#<procedure " + self.symnames[nm] + ">"
		Prim(id): return "#<builtin " + self.pnames[id] + ">"
		Pair(p):
			var s = "("
			s += self.show(self.cars[p], w)
			var cur = self.cdrs[p]
			while true:
				match cur:
					Nil: break
					Pair(q):
						s += " "
						s += self.show(self.cars[q], w)
						cur = self.cdrs[q]
					_:
						s += " . "
						s += self.show(cur, w)
						break
			s += ")"
			return s
		_: return ""

fn var Interp.flush() Unit:
	if self.out.length() > 0:
		print(self.out, end: "")
		self.out = ""

fn var Interp.emit(s: String) Unit:
	if s.length() == 0: return
	self.out += s
	self.any_out = true
	self.last_nl = s.scalar_at(s.length() - 1) == 10
	if self.out.length() > 30000:
		self.flush()

// ---------------- equality ----------------

fn Interp.eqv(a: Val, b: Val) Bool:
	match a:
		Num(x):
			match b:
				Num(y): return x == y
				_: return false
		Boolean(x):
			match b:
				Boolean(y): return x == y
				_: return false
		Sym(x):
			match b:
				Sym(y): return x == y
				_: return false
		Nil:
			match b:
				Nil: return true
				_: return false
		_: return false

fn Interp.equal(a: Val, b: Val) Bool:
	var x = a
	var y = b
	while true:
		match x:
			Pair(p):
				match y:
					Pair(q):
						if not self.equal(self.cars[p], self.cars[q]): return false
						x = self.cdrs[p]
						y = self.cdrs[q]
					_: return false
			Str(i):
				match y:
					Str(j): return self.strs[i] == self.strs[j]
					_: return false
			Clo(i):
				match y:
					Clo(j): return i == j
					_: return false
			Prim(i):
				match y:
					Prim(j): return i == j
					_: return false
			_: return self.eqv(x, y)
	return false

// ---------------- environments ----------------

fn var Interp.new_frame(names: List[Int], vals: List[Val], parent: Int) Int:
	self.frames.append(Frame(names: names, vals: vals, parent: parent))
	return self.frames.length() - 1

fn var Interp.lookup(id: Int, env: Int) Val!:
	var e = env
	while e != 0:
		cnt := self.frames[e].names.length()
		for j in 0..cnt:
			if self.frames[e].names[j] == id:
				return ok(self.frames[e].vals[j])
		e = self.frames[e].parent
	v := self.globals[id]
	match v:
		Unbound: return error(rt("unbound variable: " + self.symnames[id]))
		_: return ok(v)

fn var Interp.set_var(id: Int, v: Val, env: Int) Unit!:
	var e = env
	while e != 0:
		cnt := self.frames[e].names.length()
		for j in 0..cnt:
			if self.frames[e].names[j] == id:
				self.frames[e].vals[j] = v
				return ok(unit)
		e = self.frames[e].parent
	match self.globals[id]:
		Unbound: return error(rt("unbound variable: " + self.symnames[id]))
		_:
			self.globals[id] = v
			return ok(unit)

fn var Interp.define_var(id: Int, v: Val, env: Int) Unit:
	if env == 0:
		self.globals[id] = v
		return
	cnt := self.frames[env].names.length()
	for j in 0..cnt:
		if self.frames[env].names[j] == id:
			self.frames[env].vals[j] = v
			return
	self.frames[env].names.append(id)
	self.frames[env].vals.append(v)

// ---------------- parameters ----------------

fn var Interp.parse_params(p: Val) Closure?:
	var params = List[Int]()
	var rest = -1
	var cur = p
	while true:
		match cur:
			Nil: break
			Sym(id):
				if params.contains(id): return none
				rest = id
				break
			Pair(q):
				s := sym_id(self.cars[q])
				if s < 0: return none
				if params.contains(s): return none
				params.append(s)
				cur = self.cdrs[q]
			_: return none
	return Closure(params: params, rest: rest, body: Val.Nil, env: 0, name: -1)

fn var Interp.parse_bindings(b: Val) List[Val]?:
	var out = List[Val]()
	var cur = b
	while true:
		match cur:
			Nil: return out
			Pair(q):
				bind := self.cars[q]
				bv := self.to_vec(bind)
				if bv.is_none(): return none
				items := bv.get(List[Val]())
				if items.length() != 2: return none
				if sym_id(items[0]) < 0: return none
				out.append(bind)
				cur = self.cdrs[q]
			_: return none
	return none

fn var Interp.bind_closure(cid: Int, args: List[Val]) Int!:
	np := self.closures[cid].params.length()
	rest := self.closures[cid].rest
	n := args.length()
	if (rest < 0 and n != np) or (rest >= 0 and n < np):
		nm := self.closures[cid].name
		var cname = "lambda"
		if nm >= 0: cname = self.symnames[nm].clone()
		var e = "{np}"
		if rest >= 0: e = "at least {np}"
		return error(rt("wrong number of arguments to {cname}: expected {e}, got {n}"))
	var names = self.closures[cid].params.clone()
	var vals = List[Val]()
	for i in 0..np:
		vals.append(args[i])
	if rest >= 0:
		names.append(rest)
		var extra = List[Val]()
		for i in np..n:
			extra.append(args[i])
		vals.append(self.mklist(extra, Val.Nil))
	return ok(self.new_frame(names, vals, self.closures[cid].env))

// Evaluates all but the last form of a non-empty proper body; returns the last form.
fn var Interp.prefix(body: Val, env: Int) Val!:
	var cur = body
	while true:
		match cur:
			Pair(p):
				nxt := self.cdrs[p]
				match nxt:
					Nil: return ok(self.cars[p])
					_:
						_ := self.eval(self.cars[p], env)?
						cur = nxt
			_: return ok(Val.Void)
	return ok(Val.Void)

fn bad(name: String) Error:
	return syn("syntax error: bad form: " + name)

// ---------------- evaluator ----------------

fn var Interp.eval(expr: Val, env: Int) Val!:
	d0 := self.depth
	r := self.eval_loop(expr, env, false)
	self.depth = d0
	return r

fn var Interp.apply_proc(f: Val, args: List[Val]) Val!:
	d0 := self.depth
	r := self.apply_inner(f, args)
	self.depth = d0
	return r

fn var Interp.apply_inner(f: Val, args: List[Val]) Val!:
	match f:
		Clo(cid):
			frame := self.bind_closure(cid, args)?
			if self.depth + 1 > 10000: return error(rt("recursion limit exceeded"))
			self.depth += 1
			last := self.prefix(self.closures[cid].body, frame)?
			return self.eval_loop(last, frame, true)
		Prim(prid): return self.call_prim(prid, args)
		_: return error(rt("not a procedure: " + self.show(f, true)))

fn var Interp.eval_loop(expr0: Val, env0: Int, entered0: Bool) Val!:
	var expr = expr0
	var env = env0
	var entered = entered0
	while true:
		match expr:
			Sym(id): return self.lookup(id, env)
			Nil: return error(syn("syntax error: empty application"))
			Pair(pid):
				head := self.cars[pid]
				rest := self.cdrs[pid]
				hs := sym_id(head)
				if hs >= 0 and hs < 16:
					name := self.symnames[hs].clone()
					items_o := self.to_vec(rest)
					if items_o.is_none(): return error(bad(name))
					items := items_o.get(List[Val]())
					n := items.length()
					if hs == 0:
						if n != 1: return error(bad(name))
						return ok(items[0])
					else if hs == 1:
						if n != 2 and n != 3: return error(bad(name))
						t := self.eval(items[0], env)?
						if not is_false(t):
							expr = items[1]
						else if n == 3:
							expr = items[2]
						else:
							return ok(Val.Void)
						continue
					else if hs == 2:
						if n < 2: return error(bad(name))
						target := items[0]
						match target:
							Sym(id):
								if n != 2: return error(bad(name))
								v := self.eval(items[1], env)?
								self.name_closure(items[1], v, id)
								self.define_var(id, v, env)
								return ok(Val.Void)
							Pair(tp):
								fname := sym_id(self.cars[tp])
								if fname < 0: return error(bad(name))
								cl_o := self.parse_params(self.cdrs[tp])
								if cl_o.is_none(): return error(bad(name))
								var cl = cl_o.get(Closure(params: List[Int](), rest: -1, body: Val.Nil, env: 0, name: -1))
								cl.body = self.cdr_of(rest)
								cl.env = env
								cl.name = fname
								self.closures.append(cl)
								self.define_var(fname, Val.Clo(self.closures.length() - 1), env)
								return ok(Val.Void)
							_: return error(bad(name))
					else if hs == 3:
						if n != 2: return error(bad(name))
						id := sym_id(items[0])
						if id < 0: return error(bad(name))
						v := self.eval(items[1], env)?
						self.set_var(id, v, env)?
						return ok(Val.Void)
					else if hs == 4:
						if n < 2: return error(bad(name))
						cl_o := self.parse_params(items[0])
						if cl_o.is_none(): return error(bad(name))
						var cl = cl_o.get(Closure(params: List[Int](), rest: -1, body: Val.Nil, env: 0, name: -1))
						cl.body = self.cdr_of(rest)
						cl.env = env
						self.closures.append(cl)
						return ok(Val.Clo(self.closures.length() - 1))
					else if hs == 5:
						if n == 0: return ok(Val.Void)
						expr = self.prefix(rest, env)?
						continue
					else if hs == 6 or hs == 7 or hs == 8:
						if n < 2: return error(bad(name))
						if hs == 6 and sym_id(items[0]) >= 0:
							if n < 3: return error(bad(name))
							lname := sym_id(items[0])
							bl_o := self.parse_bindings(items[1])
							if bl_o.is_none(): return error(bad(name))
							bl := bl_o.get(List[Val]())
							var pnames = List[Int]()
							var vals = List[Val]()
							for b in bl:
								pnames.append(sym_id(self.car_of(b)))
							var cl = Closure(params: pnames.clone(), rest: -1, body: self.cdr_of(self.cdr_of(rest)), env: 0, name: lname)
							for i in 0..pnames.length():
								for j in 0..i:
									if pnames[i] == pnames[j]: return error(bad(name))
							for b in bl:
								v := self.eval(self.car_of(self.cdr_of(b)), env)?
								vals.append(v)
							var n1 = List[Int]()
							n1.append(lname)
							var v1 = List[Val]()
							v1.append(Val.Nil)
							f1 := self.new_frame(n1, v1, env)
							cl.env = f1
							self.closures.append(cl)
							cid := self.closures.length() - 1
							self.frames[f1].vals[0] = Val.Clo(cid)
							frame := self.new_frame(pnames, vals, f1)
							if not entered:
								if self.depth + 1 > 10000: return error(rt("recursion limit exceeded"))
								self.depth += 1
								entered = true
							env = frame
							expr = self.prefix(self.closures[cid].body, env)?
							continue
						bl_o := self.parse_bindings(items[0])
						if bl_o.is_none(): return error(bad(name))
						bl := bl_o.get(List[Val]())
						body := self.cdr_of(rest)
						if hs == 6:
							var names = List[Int]()
							var vals = List[Val]()
							for b in bl:
								v := self.eval(self.car_of(self.cdr_of(b)), env)?
								names.append(sym_id(self.car_of(b)))
								vals.append(v)
							env = self.new_frame(names, vals, env)
						else:
							frame := self.new_frame(List[Int](), List[Val](), env)
							for b in bl:
								v := self.eval(self.car_of(self.cdr_of(b)), frame)?
								self.define_var(sym_id(self.car_of(b)), v, frame)
							env = frame
						expr = self.prefix(body, env)?
						continue
					else if hs == 9:
						var matched = false
						for i in 0..n:
							cv_o := self.to_vec(items[i])
							if cv_o.is_none(): return error(bad(name))
							cv := cv_o.get(List[Val]())
							if cv.length() == 0: return error(bad(name))
							if sym_id(cv[0]) == 15:
								if i != n - 1 or cv.length() < 2: return error(bad(name))
								expr = self.prefix(self.cdr_of(items[i]), env)?
								matched = true
								break
							t := self.eval(cv[0], env)?
							if not is_false(t):
								if cv.length() == 1: return ok(t)
								expr = self.prefix(self.cdr_of(items[i]), env)?
								matched = true
								break
						if matched: continue
						return ok(Val.Void)
					else if hs == 10:
						if n == 0: return ok(Val.Boolean(true))
						for i in 0..n - 1:
							t := self.eval(items[i], env)?
							if is_false(t): return ok(t)
						expr = items[n - 1]
						continue
					else if hs == 11:
						if n == 0: return ok(Val.Boolean(false))
						for i in 0..n - 1:
							t := self.eval(items[i], env)?
							if not is_false(t): return ok(t)
						expr = items[n - 1]
						continue
					else if hs == 12 or hs == 13:
						if n < 2: return error(bad(name))
						t := self.eval(items[0], env)?
						var fire = not is_false(t)
						if hs == 13: fire = not fire
						if not fire: return ok(Val.Void)
						expr = self.prefix(self.cdr_of(rest), env)?
						continue
					else if hs == 14:
						if n != 2: return error(bad(name))
						r := self.eval(items[0], env)
						if v := r:
							return ok(v)
						else:
							e := r.err()
							if is_syntax(e): return error(e)
							h := self.eval(items[1], env)?
							msg := self.mkstr(e.message.clone())
							var margs = List[Val]()
							margs.append(msg)
							return self.apply_proc(h, margs)
					// hs == 15 (else) as a head is an ordinary variable
				// application
				items_o := self.to_vec(expr)
				if items_o.is_none(): return error(syn("syntax error: bad application"))
				fv := self.eval(head, env)?
				var args = List[Val]()
				var cur = rest
				while true:
					match cur:
						Pair(q):
							a := self.eval(self.cars[q], env)?
							args.append(a)
							cur = self.cdrs[q]
						_: break
				match fv:
					Clo(cid):
						frame := self.bind_closure(cid, args)?
						if not entered:
							if self.depth + 1 > 10000: return error(rt("recursion limit exceeded"))
							self.depth += 1
							entered = true
						env = frame
						expr = self.prefix(self.closures[cid].body, env)?
						continue
					Prim(prid): return self.call_prim(prid, args)
					_: return error(rt("not a procedure: " + self.show(fv, true)))
			_: return ok(expr)
	return ok(Val.Void)

fn var Interp.name_closure(e: Val, v: Val, id: Int) Unit:
	match e:
		Pair(p):
			if sym_id(self.cars[p]) == 4:
				match v:
					Clo(c):
						if self.closures[c].name < 0:
							self.closures[c].name = id
					_: return
		_: return

// ---------------- builtins ----------------

fn var Interp.reg(name: String, lo: Int, hi: Int) Unit:
	sid := self.intern_sym(name)
	self.pnames.append(name.clone())
	self.pmin.append(lo)
	self.pmax.append(hi)
	self.globals[sid] = Val.Prim(self.pnames.length() - 1)

fn var Interp.terr(name: String, kind: String, v: Val) Error:
	return rt("{name}: expected {kind}, got " + self.show(v, true))

fn var Interp.int_of(name: String, v: Val) Int!:
	match v:
		Num(n): return ok(n)
		_: return error(self.terr(name, "integer", v))

fn var Interp.str_of(name: String, v: Val) Int!:
	match v:
		Str(i): return ok(i)
		_: return error(self.terr(name, "string", v))

fn var Interp.list_of(name: String, v: Val) List[Val]!:
	if l := self.to_vec(v):
		return ok(l)
	return error(self.terr(name, "list", v))

fn var Interp.check_proc(name: String, v: Val) Unit!:
	match v:
		Clo(_): return ok(unit)
		Prim(_): return ok(unit)
		_: return error(self.terr(name, "procedure", v))

fn ovf() Error:
	return rt("integer overflow")

fn add_ck(a: Int, b: Int) Int!:
	if b > 0 and a > max_int() - b: return error(ovf())
	if b < 0 and a < min_int() - b: return error(ovf())
	return ok(a + b)

fn sub_ck(a: Int, b: Int) Int!:
	if b > 0 and a < min_int() + b: return error(ovf())
	if b < 0 and a > max_int() + b: return error(ovf())
	return ok(a - b)

fn mul_ck(a: Int, b: Int) Int!:
	if a == 0 or b == 0: return ok(0)
	if (a == -1 and b == min_int()) or (b == -1 and a == min_int()): return error(ovf())
	r := wrapping_multiply(a, b)
	if r / b != a: return error(ovf())
	return ok(r)

fn var Interp.ints_of(name: String, args: List[Val]) List[Int]!:
	var out = List[Int]()
	for a in args:
		out.append(self.int_of(name, a)?)
	return ok(out)

fn var Interp.msort(items: List[Val], less: Val) List[Val]!:
	n := items.length()
	if n <= 1: return ok(items.clone())
	mid := n / 2
	var l = List[Val]()
	var r = List[Val]()
	for i in 0..mid:
		l.append(items[i])
	for i in mid..n:
		r.append(items[i])
	ls := self.msort(l, less)?
	rs := self.msort(r, less)?
	var out = List[Val]()
	var i = 0
	var j = 0
	while i < ls.length() and j < rs.length():
		var args = List[Val]()
		args.append(rs[j])
		args.append(ls[i])
		t := self.apply_proc(less, args)?
		if is_false(t):
			out.append(ls[i])
			i += 1
		else:
			out.append(rs[j])
			j += 1
	while i < ls.length():
		out.append(ls[i])
		i += 1
	while j < rs.length():
		out.append(rs[j])
		j += 1
	return ok(out)

fn var Interp.call_prim(pid: Int, args: List[Val]) Val!:
	name := self.pnames[pid].clone()
	n := args.length()
	lo := self.pmin[pid]
	hi := self.pmax[pid]
	if n < lo or (hi >= 0 and n > hi):
		return error(rt("wrong number of arguments to {name}: expected " + arity_text(lo, hi) + ", got {n}"))
	if name == "+":
		xs := self.ints_of(name, args)?
		var acc = 0
		for x in xs:
			acc = add_ck(acc, x)?
		return ok(Val.Num(acc))
	if name == "-":
		xs := self.ints_of(name, args)?
		if n == 1:
			return ok(Val.Num(sub_ck(0, xs[0])?))
		var acc = xs[0]
		for i in 1..n:
			acc = sub_ck(acc, xs[i])?
		return ok(Val.Num(acc))
	if name == "*":
		xs := self.ints_of(name, args)?
		var acc = 1
		for x in xs:
			acc = mul_ck(acc, x)?
		return ok(Val.Num(acc))
	if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
		xs := self.ints_of(name, args)?
		for i in 0..n - 1:
			a := xs[i]
			b := xs[i + 1]
			var good = false
			if name == "=": good = a == b
			else if name == "<": good = a < b
			else if name == ">": good = a > b
			else if name == "<=": good = a <= b
			else: good = a >= b
			if not good: return ok(Val.Boolean(false))
		return ok(Val.Boolean(true))
	if name == "car":
		match args[0]:
			Pair(p): return ok(self.cars[p])
			_: return error(self.terr(name, "pair", args[0]))
	if name == "cdr":
		match args[0]:
			Pair(p): return ok(self.cdrs[p])
			_: return error(self.terr(name, "pair", args[0]))
	if name == "cons":
		return ok(self.cons(args[0], args[1]))
	if name == "null?":
		match args[0]:
			Nil: return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "not":
		return ok(Val.Boolean(is_false(args[0])))
	if name == "pair?":
		match args[0]:
			Pair(_): return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "eq?":
		return ok(Val.Boolean(self.eqv(args[0], args[1])))
	if name == "equal?":
		return ok(Val.Boolean(self.equal(args[0], args[1])))
	if name == "quotient" or name == "remainder" or name == "modulo":
		a := self.int_of(name, args[0])?
		b := self.int_of(name, args[1])?
		if b == 0: return error(rt("division by zero"))
		if name == "quotient":
			if a == min_int() and b == -1: return error(ovf())
			return ok(Val.Num(a / b))
		if b == -1: return ok(Val.Num(0))
		var r = a % b
		if name == "modulo" and r != 0 and ((r < 0) != (b < 0)): r += b
		return ok(Val.Num(r))
	if name == "abs":
		a := self.int_of(name, args[0])?
		if a == min_int(): return error(ovf())
		if a < 0: return ok(Val.Num(-a))
		return ok(Val.Num(a))
	if name == "min" or name == "max":
		xs := self.ints_of(name, args)?
		var best = xs[0]
		for x in xs:
			if name == "min" and x < best: best = x
			if name == "max" and x > best: best = x
		return ok(Val.Num(best))
	if name == "zero?" or name == "even?" or name == "odd?":
		a := self.int_of(name, args[0])?
		if name == "zero?": return ok(Val.Boolean(a == 0))
		if name == "even?": return ok(Val.Boolean(a % 2 == 0))
		return ok(Val.Boolean(a % 2 != 0))
	if name == "list?":
		return ok(Val.Boolean(self.to_vec(args[0]).is_some()))
	if name == "number?":
		match args[0]:
			Num(_): return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "string?":
		match args[0]:
			Str(_): return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "symbol?":
		match args[0]:
			Sym(_): return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "boolean?":
		match args[0]:
			Boolean(_): return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "procedure?":
		match args[0]:
			Clo(_): return ok(Val.Boolean(true))
			Prim(_): return ok(Val.Boolean(true))
			_: return ok(Val.Boolean(false))
	if name == "cadr" or name == "cddr" or name == "caddr":
		var cur = args[0]
		var steps = 2
		if name == "caddr": steps = 3
		for i in 0..steps:
			match cur:
				Pair(p):
					if i == steps - 1 and name != "cddr":
						cur = self.cars[p]
					else:
						cur = self.cdrs[p]
				_: return error(self.terr(name, "pair", cur))
		return ok(cur)
	if name == "set-car!" or name == "set-cdr!":
		match args[0]:
			Pair(p):
				if name == "set-car!": self.cars[p] = args[1]
				else: self.cdrs[p] = args[1]
				return ok(Val.Void)
			_: return error(self.terr(name, "pair", args[0]))
	if name == "list":
		return ok(self.mklist(args, Val.Nil))
	if name == "length":
		l := self.list_of(name, args[0])?
		return ok(Val.Num(l.length()))
	if name == "append":
		if n == 0: return ok(Val.Nil)
		var lists = List[List[Val]]()
		for i in 0..n - 1:
			lists.append(self.list_of(name, args[i])?)
		var r = args[n - 1]
		var i = n - 2
		while i >= 0:
			r = self.mklist(lists[i], r)
			i -= 1
		return ok(r)
	if name == "reverse":
		l := self.list_of(name, args[0])?
		var r = Val.Nil
		for x in l:
			r = self.cons(x, r)
		return ok(r)
	if name == "list-ref" or name == "list-tail":
		l := self.list_of(name, args[0])?
		k := self.int_of(name, args[1])?
		if name == "list-ref":
			if k < 0 or k >= l.length(): return error(rt("list-ref: index out of range"))
			return ok(l[k])
		if k < 0 or k > l.length(): return error(rt("list-tail: index out of range"))
		var cur = args[0]
		for i in 0..k:
			cur = self.cdr_of(cur)
		return ok(cur)
	if name == "range":
		a := self.int_of(name, args[0])?
		b := self.int_of(name, args[1])?
		var items = List[Val]()
		var i = a
		while i < b:
			items.append(Val.Num(i))
			i += 1
		return ok(self.mklist(items, Val.Nil))
	if name == "assoc" or name == "member":
		l := self.list_of(name, args[1])?
		var cur = args[1]
		for x in l:
			if name == "assoc":
				match x:
					Pair(p):
						if self.equal(self.cars[p], args[0]): return ok(x)
					_: return error(self.terr(name, "pair", x))
			else:
				if self.equal(x, args[0]): return ok(cur)
			cur = self.cdr_of(cur)
		return ok(Val.Boolean(false))
	if name == "map" or name == "for-each":
		self.check_proc(name, args[0])?
		var lists = List[List[Val]]()
		for i in 1..n:
			lists.append(self.list_of(name, args[i])?)
		var m = lists[0].length()
		for l in lists:
			if l.length() < m: m = l.length()
		var results = List[Val]()
		for i in 0..m:
			var cargs = List[Val]()
			for l in lists:
				cargs.append(l[i])
			r := self.apply_proc(args[0], cargs)?
			if name == "map": results.append(r)
		if name == "map": return ok(self.mklist(results, Val.Nil))
		return ok(Val.Void)
	if name == "filter":
		self.check_proc(name, args[0])?
		l := self.list_of(name, args[1])?
		var results = List[Val]()
		for x in l:
			var cargs = List[Val]()
			cargs.append(x)
			r := self.apply_proc(args[0], cargs)?
			if not is_false(r): results.append(x)
		return ok(self.mklist(results, Val.Nil))
	if name == "fold" or name == "foldr":
		self.check_proc(name, args[0])?
		l := self.list_of(name, args[2])?
		var acc = args[1]
		if name == "fold":
			for x in l:
				var cargs = List[Val]()
				cargs.append(acc)
				cargs.append(x)
				acc = self.apply_proc(args[0], cargs)?
		else:
			var i = l.length() - 1
			while i >= 0:
				var cargs = List[Val]()
				cargs.append(l[i])
				cargs.append(acc)
				acc = self.apply_proc(args[0], cargs)?
				i -= 1
		return ok(acc)
	if name == "apply":
		self.check_proc(name, args[0])?
		last := self.list_of(name, args[n - 1])?
		var cargs = List[Val]()
		for i in 1..n - 1:
			cargs.append(args[i])
		for x in last:
			cargs.append(x)
		return self.apply_proc(args[0], cargs)
	if name == "sort":
		self.check_proc(name, args[1])?
		l := self.list_of(name, args[0])?
		sorted := self.msort(l, args[1])?
		return ok(self.mklist(sorted, Val.Nil))
	if name == "display" or name == "write":
		self.emit(self.show(args[0], name == "write"))
		return ok(Val.Void)
	if name == "newline":
		self.emit("\n")
		return ok(Val.Void)
	if name == "void":
		return ok(Val.Void)
	if name == "error":
		mi := self.str_of(name, args[0])?
		var msg = self.strs[mi].clone()
		for i in 1..n:
			msg += " "
			msg += self.show(args[i], true)
		return error(rt(msg))
	if name == "string-length":
		i := self.str_of(name, args[0])?
		return ok(Val.Num(self.strs[i].length()))
	if name == "string-append":
		var s = ""
		for a in args:
			i := self.str_of(name, a)?
			s += self.strs[i]
		return ok(self.mkstr(s))
	if name == "substring":
		i := self.str_of(name, args[0])?
		a := self.int_of(name, args[1])?
		b := self.int_of(name, args[2])?
		len := self.strs[i].length()
		if a < 0 or a > b or b > len: return error(rt("substring: index out of range"))
		return ok(self.mkstr(self.strs[i].view(a, b).clone()))
	if name == "string-ref":
		i := self.str_of(name, args[0])?
		k := self.int_of(name, args[1])?
		if k < 0 or k >= self.strs[i].length(): return error(rt("string-ref: index out of range"))
		return ok(self.mkstr(self.strs[i].view(k, k + 1).clone()))
	if name == "string=?" or name == "string<?":
		i := self.str_of(name, args[0])?
		j := self.str_of(name, args[1])?
		if name == "string=?": return ok(Val.Boolean(self.strs[i] == self.strs[j]))
		return ok(Val.Boolean(self.strs[i] < self.strs[j]))
	if name == "string-upcase" or name == "string-downcase":
		i := self.str_of(name, args[0])?
		var s = ""
		len := self.strs[i].length()
		for k in 0..len:
			c := self.strs[i].scalar_at(k)
			if name == "string-upcase" and c >= 97 and c <= 122:
				s += self.strs[i].view(k, k + 1).upper()
			else if name == "string-downcase" and c >= 65 and c <= 90:
				s += self.strs[i].view(k, k + 1).lower()
			else:
				s += self.strs[i].view(k, k + 1)
		return ok(self.mkstr(s))
	if name == "string->number":
		i := self.str_of(name, args[0])?
		t := self.strs[i].clone()
		if is_int_tok(t):
			if v := parse_digits(t):
				return ok(Val.Num(v))
		return ok(Val.Boolean(false))
	if name == "number->string":
		k := self.int_of(name, args[0])?
		return ok(self.mkstr("{k}"))
	if name == "string->symbol":
		i := self.str_of(name, args[0])?
		t := self.strs[i].clone()
		return ok(Val.Sym(self.intern_sym(t)))
	if name == "symbol->string":
		match args[0]:
			Sym(id): return ok(self.mkstr(self.symnames[id].clone()))
			_: return error(self.terr(name, "symbol", args[0]))
	if name == "string->list":
		i := self.str_of(name, args[0])?
		var items = List[Val]()
		len := self.strs[i].length()
		for k in 0..len:
			items.append(self.mkstr(self.strs[i].view(k, k + 1).clone()))
		return ok(self.mklist(items, Val.Nil))
	if name == "list->string":
		l := self.list_of(name, args[0])?
		var s = ""
		for x in l:
			i := self.str_of(name, x)?
			s += self.strs[i]
		return ok(self.mkstr(s))
	if name == "string-join":
		l := self.list_of(name, args[0])?
		si := self.str_of(name, args[1])?
		var s = ""
		var first = true
		for x in l:
			i := self.str_of(name, x)?
			if not first: s += self.strs[si]
			first = false
			s += self.strs[i]
		return ok(self.mkstr(s))
	if name == "string-split":
		i := self.str_of(name, args[0])?
		si := self.str_of(name, args[1])?
		if self.strs[si].length() != 1: return error(rt("string-split: separator must be one character"))
		sep := self.strs[si].scalar_at(0)
		var parts = List[Val]()
		len := self.strs[i].length()
		var start = 0
		for k in 0..len:
			if self.strs[i].scalar_at(k) == sep:
				parts.append(self.mkstr(self.strs[i].view(start, k).clone()))
				start = k + 1
		parts.append(self.mkstr(self.strs[i].view(start, len).clone()))
		return ok(self.mklist(parts, Val.Nil))
	if name == "string-contains?":
		i := self.str_of(name, args[0])?
		j := self.str_of(name, args[1])?
		return ok(Val.Boolean(self.strs[i].contains(self.strs[j])))
	return error(rt("internal: unknown builtin " + name))

fn var Interp.setup() Unit:
	// special form names must occupy ids 0..15 in this order
	names := ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try", "else"]
	for nm in names:
		self.intern_sym(nm)
	self.reg("+", 0, -1)
	self.reg("-", 1, -1)
	self.reg("*", 0, -1)
	self.reg("quotient", 2, 2)
	self.reg("remainder", 2, 2)
	self.reg("modulo", 2, 2)
	self.reg("abs", 1, 1)
	self.reg("min", 1, -1)
	self.reg("max", 1, -1)
	self.reg("=", 2, -1)
	self.reg("<", 2, -1)
	self.reg(">", 2, -1)
	self.reg("<=", 2, -1)
	self.reg(">=", 2, -1)
	for nm in ["zero?", "even?", "odd?", "not", "null?", "pair?", "list?", "number?", "string?", "symbol?", "boolean?", "procedure?"]:
		self.reg(nm, 1, 1)
	self.reg("eq?", 2, 2)
	self.reg("equal?", 2, 2)
	self.reg("cons", 2, 2)
	for nm in ["car", "cdr", "cadr", "cddr", "caddr", "length", "reverse"]:
		self.reg(nm, 1, 1)
	self.reg("set-car!", 2, 2)
	self.reg("set-cdr!", 2, 2)
	self.reg("list", 0, -1)
	self.reg("append", 0, -1)
	for nm in ["list-ref", "list-tail", "range", "assoc", "member", "filter", "sort", "string-ref", "string=?", "string<?", "string-join", "string-split", "string-contains?"]:
		self.reg(nm, 2, 2)
	self.reg("map", 2, -1)
	self.reg("for-each", 2, -1)
	self.reg("fold", 3, 3)
	self.reg("foldr", 3, 3)
	self.reg("apply", 2, -1)
	for nm in ["string-length", "string-upcase", "string-downcase", "string->number", "number->string", "string->symbol", "symbol->string", "string->list", "list->string", "display", "write"]:
		self.reg(nm, 1, 1)
	self.reg("string-append", 0, -1)
	self.reg("substring", 3, 3)
	self.reg("newline", 0, 0)
	self.reg("void", 0, 0)
	self.reg("error", 1, -1)

// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().get("")
	var it = Interp()
	it.src = text
	it.frames.append(Frame(names: List[Int](), vals: List[Val](), parent: 0))
	it.setup()
	while true:
		it.skip_ws()
		if it.pos >= it.src.length(): break
		r := it.read_datum()
		if d := r:
			r2 := it.eval(d, 0)
			if _v := r2:
				continue
			else:
				msg := r2.err().message.clone()
				if it.any_out and not it.last_nl: it.emit("\n")
				it.emit("error: " + msg + "\n")
				break
		else:
			msg := r.err().message.clone()
			if it.any_out and not it.last_nl: it.emit("\n")
			it.emit("error: " + msg + "\n")
			break
	it.flush()
