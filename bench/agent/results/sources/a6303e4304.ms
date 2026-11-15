import Bytes from "@std/bytes.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

enum Value:
	VNil
	VVoid
	VBool(b: Bool)
	VInt(n: Int)
	VSym(id: Int)
	VStr(id: Int)
	VPair(id: Int)
	VProc(id: Int)
	VBuiltin(id: Int)

type Closure:
	params: List[Int]
	rest: Int
	body: Value
	env: Int
	name: Int

type Frame:
	parent: Int
	names: List[Int]
	cells: List[Int]

type Params:
	names: List[Int]
	rest: Int

type Interp:
	src: Bytes
	text: String
	pos: Int = 0
	strs: List[String]
	sym_names: List[String]
	sym_ids: Map[String, Int]
	cars: List[Value]
	cdrs: List[Value]
	closures: List[Closure]
	bnames: List[String]
	bmin: List[Int]
	bmax: List[Int]
	frames: List[Frame]
	cells: List[Value]
	globals: Map[Int, Int]
	out: String = ""
	depth: Int = 0
	s_else: Int = 0
	s_lambda: Int = 0

fn int_min() Int: -9223372036854775807 - 1
fn int_max() Int: 9223372036854775807

fn overflow() Error: Error("integer overflow")

fn add_c(a: Int, b: Int) Int!:
	if b > 0 and a > int_max() - b: return error(overflow())
	if b < 0 and a < int_min() - b: return error(overflow())
	return ok(a + b)

fn sub_c(a: Int, b: Int) Int!:
	if b > 0 and a < int_min() + b: return error(overflow())
	if b < 0 and a > int_max() + b: return error(overflow())
	return ok(a - b)

fn mul_c(a: Int, b: Int) Int!:
	if a == 0 or b == 0: return ok(0)
	if a == -1:
		if b == int_min(): return error(overflow())
		return ok(-b)
	if b == -1:
		if a == int_min(): return error(overflow())
		return ok(-a)
	if a > 0 and b > 0:
		if a > int_max() / b: return error(overflow())
	else if a > 0 and b < 0:
		if b < int_min() / a: return error(overflow())
	else if a < 0 and b > 0:
		if a < int_min() / b: return error(overflow())
	else:
		if a < int_max() / b: return error(overflow())
	return ok(a * b)

fn is_ws(c: Int) Bool: c == 32 or c == 9 or c == 10 or c == 13

fn is_delim(c: Int) Bool: is_ws(c) or c == 40 or c == 41 or c == 34 or c == 59

fn is_int_token(t: String) Bool:
	bs := t.as_bytes()
	n := bs.length()
	var i = 0
	if n > 0 and bs.get(0).to_int() == 45: i = 1
	if i >= n: return false
	while i < n:
		c := bs.get(i).to_int()
		if c < 48 or c > 57: return false
		i += 1
	return true

fn pair_id(v: Value) Int:
	match v:
		VPair(p): return p
		_: return -1

fn sym_id(v: Value) Int:
	match v:
		VSym(i): return i
		_: return -1

fn truthy(v: Value) Bool:
	match v:
		VBool(b): return b
		_: return true

fn quote_string(s: String) String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t") + "\""

fn fail(msg: String) Value!:
	return error(Error(msg))

fn Interp.terr(name: String, kind: String, v: Value) Error:
	return Error("{name}: expected {kind}, got {self.show(v, true)}")

fn Interp.show(v: Value, write: Bool) String:
	match v:
		VNil: return "()"
		VVoid: return "#<void>"
		VBool(b): return if b: "#t" else: "#f"
		VInt(n): return "{n}"
		VSym(id): return self.sym_names[id].clone()
		VStr(id):
			if write: return quote_string(self.strs[id])
			return self.strs[id].clone()
		VProc(id):
			nm := self.closures[id].name
			if nm < 0: return "#<procedure>"
			return "#<procedure {self.sym_names[nm]}>"
		VBuiltin(id): return "#<builtin {self.bnames[id]}>"
		VPair(p):
			var s = "(" + self.show(self.cars[p], write)
			var cur = self.cdrs[p]
			var going = true
			while going:
				match cur:
					VPair(q):
						s += " " + self.show(self.cars[q], write)
						cur = self.cdrs[q]
					VNil:
						going = false
					_:
						s += " . " + self.show(cur, write)
						going = false
			return s + ")"

fn var Interp.intern(name: String) Int:
	if id := self.sym_ids.get(name):
		return id
	id := self.sym_names.length()
	self.sym_names.append(name.clone())
	self.sym_ids[name.clone()] = id
	return id

fn var Interp.mk_str(s: String) Value:
	self.strs.append(s.clone())
	return Value.VStr(self.strs.length() - 1)

fn var Interp.cons(a: Value, d: Value) Value:
	self.cars.append(a)
	self.cdrs.append(d)
	return Value.VPair(self.cars.length() - 1)

fn var Interp.from_vec(items: List[Value], tail: Value) Value:
	var r = tail
	var i = items.length() - 1
	while i >= 0:
		r = self.cons(items[i], r)
		i -= 1
	return r

fn Interp.to_vec(v: Value) List[Value]?:
	var out = List[Value]()
	var cur = v
	while true:
		match cur:
			VNil: return out
			VPair(p):
				out.append(self.cars[p])
				cur = self.cdrs[p]
			_: return none
	return none

fn Interp.nth_tail(v: Value, k: Int) Value:
	var cur = v
	var i = 0
	while i < k:
		p := pair_id(cur)
		if p < 0: return cur
		cur = self.cdrs[p]
		i += 1
	return cur

fn var Interp.new_cell(v: Value) Int:
	self.cells.append(v)
	return self.cells.length() - 1

fn var Interp.new_frame(parent: Int) Int:
	self.frames.append(Frame(parent: parent, names: List[Int](), cells: List[Int]()))
	return self.frames.length() - 1

fn Interp.find_cell(id: Int, env: Int) Int:
	var cur = env
	while cur != 0:
		f := self.frames[cur]
		for i in 0..f.names.length():
			if f.names[i] == id: return f.cells[i]
		cur = f.parent
	return self.globals.get_or(id, -1)

fn Interp.lookup(id: Int, env: Int) Value!:
	c := self.find_cell(id, env)
	if c < 0: return fail("unbound variable: {self.sym_names[id]}")
	return ok(self.cells[c])

fn Interp.frame_find(env: Int, id: Int) Int:
	f := self.frames[env]
	for i in 0..f.names.length():
		if f.names[i] == id: return f.cells[i]
	return -1

fn var Interp.bind(env: Int, id: Int, v: Value) Unit:
	if env == 0:
		c := self.globals.get_or(id, -1)
		if c >= 0:
			self.cells[c] = v
		else:
			nc := self.new_cell(v)
			self.globals[id] = nc
		return
	found := self.frame_find(env, id)
	if found >= 0:
		self.cells[found] = v
		return
	nc := self.new_cell(v)
	self.frames[env].names.append(id)
	self.frames[env].cells.append(nc)

fn Interp.parse_params(p: Value) Params?:
	var names = List[Int]()
	var rest = -1
	var cur = p
	var going = true
	while going:
		match cur:
			VNil: going = false
			VSym(i):
				if names.contains(i): return none
				rest = i
				going = false
			VPair(q):
				s := sym_id(self.cars[q])
				if s < 0: return none
				if names.contains(s): return none
				names.append(s)
				cur = self.cdrs[q]
			_: return none
	return Params(names: names, rest: rest)

fn var Interp.new_closure(ps: Params, body: Value, env: Int, name: Int) Value:
	self.closures.append(Closure(params: ps.names.clone(), rest: ps.rest, body: body, env: env, name: name))
	return Value.VProc(self.closures.length() - 1)

fn Interp.closure_name(cid: Int) String:
	nm := self.closures[cid].name
	if nm < 0: return "lambda"
	return self.sym_names[nm].clone()

fn var Interp.bind_args(cid: Int, args: List[Value]) Int!:
	nparams := self.closures[cid].params.length()
	rest := self.closures[cid].rest
	cenv := self.closures[cid].env
	n := args.length()
	if rest < 0:
		if n != nparams:
			return error(Error("wrong number of arguments to {self.closure_name(cid)}: expected {nparams}, got {n}"))
	else:
		if n < nparams:
			return error(Error("wrong number of arguments to {self.closure_name(cid)}: expected at least {nparams}, got {n}"))
	fid := self.new_frame(cenv)
	for i in 0..nparams:
		pid := self.closures[cid].params[i]
		c := self.new_cell(args[i])
		self.frames[fid].names.append(pid)
		self.frames[fid].cells.append(c)
	if rest >= 0:
		var tail = List[Value]()
		for i in nparams..n:
			tail.append(args[i])
		lst := self.from_vec(tail, Value.VNil)
		c := self.new_cell(lst)
		self.frames[fid].names.append(rest)
		self.frames[fid].cells.append(c)
	return ok(fid)

fn var Interp.bump() Unit!:
	if self.depth >= 10000: return error(Error("recursion limit exceeded"))
	self.depth += 1
	return ok(unit)

// Evaluates all but the last expression of a body; returns the last expression.
fn var Interp.body_prefix(body: Value, env: Int) Value!:
	var b = body
	while true:
		p := pair_id(b)
		nx := self.cdrs[p]
		if pair_id(nx) < 0: return ok(self.cars[p])
		_v := self.eval(self.cars[p], env)?
		b = nx
	return ok(Value.VVoid)

fn var Interp.call_proc(f: Value, args: List[Value]) Value!:
	match f:
		VProc(cid):
			saved := self.depth
			self.bump()?
			env := self.bind_args(cid, args)?
			last := self.body_prefix(self.closures[cid].body, env)?
			r := self.eval(last, env)?
			self.depth = saved
			return ok(r)
		VBuiltin(bid): return self.call_builtin(bid, args)
		_: return fail("not a procedure: {self.show(f, true)}")

fn var Interp.eval(e: Value, env: Int) Value!:
	saved := self.depth
	r := self.eval_loop(e, env)
	self.depth = saved
	return r

fn Interp.bad(hs: Int) Value!:
	return fail("syntax error: bad form: {self.sym_names[hs]}")

fn var Interp.eval_loop(e0: Value, env0: Int) Value!:
	var e = e0
	var env = env0
	var counted = false
	while true:
		p := pair_id(e)
		if p < 0:
			match e:
				VSym(id): return self.lookup(id, env)
				VNil: return fail("syntax error: empty application")
				_: return ok(e)
		hs := sym_id(self.cars[p])
		if hs >= 0 and hs < 15:
			xsopt := self.to_vec(e)
			if xsopt.is_none(): return self.bad(hs)
			xs := xsopt.get(List[Value]())
			n := xs.length()
			if hs == 0:
				if n != 2: return self.bad(hs)
				return ok(xs[1])
			if hs == 1:
				if n != 3 and n != 4: return self.bad(hs)
				t := self.eval(xs[1], env)?
				if truthy(t):
					e = xs[2]
					continue
				if n == 4:
					e = xs[3]
					continue
				return ok(Value.VVoid)
			if hs == 2:
				if n < 3: return self.bad(hs)
				target := xs[1]
				ts := sym_id(target)
				if ts >= 0:
					if n != 3: return self.bad(hs)
					v := self.eval(xs[2], env)?
					lp := pair_id(xs[2])
					if lp >= 0 and sym_id(self.cars[lp]) == self.s_lambda:
						vp := match v:
							VProc(cid): cid
							_: -1
						if vp >= 0: self.closures[vp].name = ts
					self.bind(env, ts, v)
					return ok(Value.VVoid)
				tp := pair_id(target)
				if tp < 0: return self.bad(hs)
				fname := sym_id(self.cars[tp])
				if fname < 0: return self.bad(hs)
				ps := self.parse_params(self.cdrs[tp])
				if ps.is_none(): return self.bad(hs)
				pv := ps.get(Params(names: List[Int](), rest: -1))
				f := self.new_closure(pv, self.nth_tail(e, 2), env, fname)
				self.bind(env, fname, f)
				return ok(Value.VVoid)
			if hs == 3:
				if n != 3: return self.bad(hs)
				ts := sym_id(xs[1])
				if ts < 0: return self.bad(hs)
				v := self.eval(xs[2], env)?
				c := self.find_cell(ts, env)
				if c < 0: return fail("unbound variable: {self.sym_names[ts]}")
				self.cells[c] = v
				return ok(Value.VVoid)
			if hs == 4:
				if n < 3: return self.bad(hs)
				ps := self.parse_params(xs[1])
				if ps.is_none(): return self.bad(hs)
				pv := ps.get(Params(names: List[Int](), rest: -1))
				return ok(self.new_closure(pv, self.nth_tail(e, 2), env, -1))
			if hs == 5:
				if n == 1: return ok(Value.VVoid)
				for i in 1..n - 1:
					_v := self.eval(xs[i], env)?
				e = xs[n - 1]
				continue
			if hs == 6 or hs == 7 or hs == 8:
				if n < 3: return self.bad(hs)
				named := hs == 6 and sym_id(xs[1]) >= 0
				if named and n < 4: return self.bad(hs)
				bidx := if named: 2 else: 1
				bodystart := bidx + 1
				binds_opt := self.to_vec(xs[bidx])
				if binds_opt.is_none(): return self.bad(hs)
				binds := binds_opt.get(List[Value]())
				var bnames = List[Int]()
				var binits = List[Value]()
				for b in binds:
					bv := self.to_vec(b)
					if bv.is_none(): return self.bad(hs)
					bl := bv.get(List[Value]())
					if bl.length() != 2: return self.bad(hs)
					bn := sym_id(bl[0])
					if bn < 0: return self.bad(hs)
					bnames.append(bn)
					binits.append(bl[1])
				if named:
					ps := Params(names: bnames.clone(), rest: -1)
					var seen = Set[Int]()
					for bn in bnames:
						if seen.contains(bn): return self.bad(hs)
						seen.add(bn)
					var vals = List[Value]()
					for i in 0..binits.length():
						vals.append(self.eval(binits[i], env)?)
					f1 := self.new_frame(env)
					nm := sym_id(xs[1])
					clo := self.new_closure(ps, self.nth_tail(e, 3), f1, nm)
					self.bind(f1, nm, clo)
					cid := match clo:
						VProc(c): c
						_: -1
					if not counted:
						self.bump()?
						counted = true
					nenv := self.bind_args(cid, vals)?
					e = self.body_prefix(self.nth_tail(e, 3), nenv)?
					env = nenv
					continue
				var nenv = 0
				if hs == 6:
					var vals = List[Value]()
					for i in 0..binits.length():
						vals.append(self.eval(binits[i], env)?)
					nenv = self.new_frame(env)
					for i in 0..bnames.length():
						self.bind(nenv, bnames[i], vals[i])
				else:
					nenv = self.new_frame(env)
					for i in 0..bnames.length():
						v := self.eval(binits[i], nenv)?
						self.bind(nenv, bnames[i], v)
				for i in bodystart..n - 1:
					_v := self.eval(xs[i], nenv)?
				e = xs[n - 1]
				env = nenv
				continue
			if hs == 9:
				var clauses = self.cdrs[p]
				var matched = false
				while not matched:
					cp := pair_id(clauses)
					if cp < 0:
						match clauses:
							VNil: return ok(Value.VVoid)
							_: return self.bad(hs)
					cl_opt := self.to_vec(self.cars[cp])
					if cl_opt.is_none(): return self.bad(hs)
					cl := cl_opt.get(List[Value]())
					if cl.length() == 0: return self.bad(hs)
					islast := pair_id(self.cdrs[cp]) < 0
					if sym_id(cl[0]) == self.s_else:
						if not islast or cl.length() < 2: return self.bad(hs)
						for i in 1..cl.length() - 1:
							_v := self.eval(cl[i], env)?
						e = cl[cl.length() - 1]
						matched = true
					else:
						t := self.eval(cl[0], env)?
						if truthy(t):
							if cl.length() == 1: return ok(t)
							for i in 1..cl.length() - 1:
								_v := self.eval(cl[i], env)?
							e = cl[cl.length() - 1]
							matched = true
						else:
							clauses = self.cdrs[cp]
				continue
			if hs == 10 or hs == 11:
				if n == 1: return ok(Value.VBool(hs == 10))
				for i in 1..n - 1:
					v := self.eval(xs[i], env)?
					if hs == 10 and not truthy(v): return ok(v)
					if hs == 11 and truthy(v): return ok(v)
				e = xs[n - 1]
				continue
			if hs == 12 or hs == 13:
				if n < 3: return self.bad(hs)
				t := self.eval(xs[1], env)?
				fire := if hs == 12: truthy(t) else: not truthy(t)
				if not fire: return ok(Value.VVoid)
				for i in 2..n - 1:
					_v := self.eval(xs[i], env)?
				e = xs[n - 1]
				continue
			if hs == 14:
				if n != 3: return self.bad(hs)
				dsaved := self.depth
				r := self.eval(xs[1], env)
				if v := r:
					return ok(v)
				msg := r.err().message
				if msg.starts_with("syntax error:"): return r
				self.depth = dsaved
				handler := self.eval(xs[2], env)?
				ms := self.mk_str(msg)
				var hargs = List[Value]()
				hargs.append(ms)
				return self.call_proc(handler, hargs)
		// application
		xsopt := self.to_vec(e)
		if xsopt.is_none(): return fail("syntax error: bad application")
		xs := xsopt.get(List[Value]())
		f := self.eval(xs[0], env)?
		var args = List[Value]()
		for i in 1..xs.length():
			args.append(self.eval(xs[i], env)?)
		match f:
			VProc(cid):
				if not counted:
					self.bump()?
					counted = true
				nenv := self.bind_args(cid, args)?
				e = self.body_prefix(self.closures[cid].body, nenv)?
				env = nenv
				continue
			VBuiltin(bid): return self.call_builtin(bid, args)
			_: return fail("not a procedure: {self.show(f, true)}")
	return ok(Value.VVoid)

// ---------- builtins ----------

fn var Interp.reg(name: String, mn: Int, mx: Int) Unit:
	self.bnames.append(name.clone())
	self.bmin.append(mn)
	self.bmax.append(mx)
	id := self.bnames.length() - 1
	sid := self.intern(name)
	c := self.new_cell(Value.VBuiltin(id))
	self.globals[sid] = c

fn Interp.int_arg(name: String, v: Value) Int!:
	match v:
		VInt(n): return ok(n)
		_: return error(self.terr(name, "integer", v))

fn Interp.str_arg(name: String, v: Value) String!:
	match v:
		VStr(id): return ok(self.strs[id].clone())
		_: return error(self.terr(name, "string", v))

fn Interp.list_arg(name: String, v: Value) List[Value]!:
	o := self.to_vec(v)
	if o.is_none(): return error(self.terr(name, "list", v))
	return ok(o.get(List[Value]()))

fn Interp.proc_arg(name: String, v: Value) Unit!:
	match v:
		VProc(_c): return ok(unit)
		VBuiltin(_b): return ok(unit)
		_: return error(self.terr(name, "procedure", v))

fn Interp.equal(a: Value, b: Value) Bool:
	match a:
		VNil:
			match b:
				VNil: return true
				_: return false
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
		VProc(x):
			match b:
				VProc(y): return x == y
				_: return false
		VBuiltin(x):
			match b:
				VBuiltin(y): return x == y
				_: return false
		VPair(_x):
			match b:
				VPair(_y):
					var l = a
					var r = b
					while true:
						lp := pair_id(l)
						rp := pair_id(r)
						if lp < 0 or rp < 0: return self.equal(l, r)
						if not self.equal(self.cars[lp], self.cars[rp]): return false
						l = self.cdrs[lp]
						r = self.cdrs[rp]
					return false
				_: return false
		VVoid: return false

fn Interp.eq(a: Value, b: Value) Bool:
	match a:
		VNil:
			match b:
				VNil: return true
				_: return false
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

fn Interp.cxr(name: String, v: Value, steps: String) Value!:
	var cur = v
	for ch in steps.chars():
		p := pair_id(cur)
		if p < 0: return error(self.terr(name, "pair", cur))
		if ch == "a":
			cur = self.cars[p]
		else:
			cur = self.cdrs[p]
	return ok(cur)

fn var Interp.msort(items: List[Value], less: Value) List[Value]!:
	n := items.length()
	if n <= 1: return ok(items.clone())
	mid := n / 2
	var left = List[Value]()
	var right = List[Value]()
	for i in 0..mid:
		left.append(items[i])
	for i in mid..n:
		right.append(items[i])
	ls := self.msort(left, less)?
	rs := self.msort(right, less)?
	var out = List[Value]()
	var i = 0
	var j = 0
	while i < ls.length() and j < rs.length():
		var args = List[Value]()
		args.append(rs[j])
		args.append(ls[i])
		res := self.call_proc(less, args)?
		if truthy(res):
			out.append(rs[j])
			j += 1
		else:
			out.append(ls[i])
			i += 1
	while i < ls.length():
		out.append(ls[i])
		i += 1
	while j < rs.length():
		out.append(rs[j])
		j += 1
	return ok(out)

fn var Interp.call_builtin(bid: Int, args: List[Value]) Value!:
	name := self.bnames[bid].clone()
	n := args.length()
	mn := self.bmin[bid]
	mx := self.bmax[bid]
	if n < mn or (mx >= 0 and n > mx):
		exp := if mn == mx: "{mn}" else if mx < 0: "at least {mn}" else: "{mn} to {mx}"
		return fail("wrong number of arguments to {name}: expected {exp}, got {n}")
	if name == "+" or name == "*":
		var nums = List[Int]()
		for a in args:
			nums.append(self.int_arg(name, a)?)
		var acc = if name == "+": 0 else: 1
		for x in nums:
			if name == "+":
				acc = add_c(acc, x)?
			else:
				acc = mul_c(acc, x)?
		return ok(Value.VInt(acc))
	if name == "-":
		var nums = List[Int]()
		for a in args:
			nums.append(self.int_arg(name, a)?)
		if n == 1: return ok(Value.VInt(sub_c(0, nums[0])?))
		var acc = nums[0]
		for i in 1..n:
			acc = sub_c(acc, nums[i])?
		return ok(Value.VInt(acc))
	if name == "=" or name == "<" or name == ">" or name == "<=" or name == ">=":
		var nums = List[Int]()
		for a in args:
			nums.append(self.int_arg(name, a)?)
		for i in 0..n - 1:
			a := nums[i]
			b := nums[i + 1]
			ok_c := if name == "=": a == b else if name == "<": a < b else if name == ">": a > b else if name == "<=": a <= b else: a >= b
			if not ok_c: return ok(Value.VBool(false))
		return ok(Value.VBool(true))
	if name == "car":
		return self.cxr(name, args[0], "a")
	if name == "cdr":
		return self.cxr(name, args[0], "d")
	if name == "cadr": return self.cxr(name, args[0], "da")
	if name == "cddr": return self.cxr(name, args[0], "dd")
	if name == "caddr": return self.cxr(name, args[0], "dda")
	if name == "cons": return ok(self.cons(args[0], args[1]))
	if name == "null?":
		match args[0]:
			VNil: return ok(Value.VBool(true))
			_: return ok(Value.VBool(false))
	if name == "pair?": return ok(Value.VBool(pair_id(args[0]) >= 0))
	if name == "not":
		match args[0]:
			VBool(b): return ok(Value.VBool(not b))
			_: return ok(Value.VBool(false))
	if name == "eq?": return ok(Value.VBool(self.eq(args[0], args[1])))
	if name == "equal?": return ok(Value.VBool(self.equal(args[0], args[1])))
	if name == "list": return ok(self.from_vec(args, Value.VNil))
	if name == "zero?" or name == "even?" or name == "odd?":
		x := self.int_arg(name, args[0])?
		if name == "zero?": return ok(Value.VBool(x == 0))
		r := if x % 2 == 0: 0 else: 1
		if name == "even?": return ok(Value.VBool(r == 0))
		return ok(Value.VBool(r == 1))
	if name == "quotient" or name == "remainder" or name == "modulo":
		a := self.int_arg(name, args[0])?
		b := self.int_arg(name, args[1])?
		if b == 0: return fail("division by zero")
		if name == "quotient":
			if b == -1: return ok(Value.VInt(sub_c(0, a)?))
			return ok(Value.VInt(a / b))
		if b == -1: return ok(Value.VInt(0))
		var r = a % b
		if name == "modulo" and r != 0 and ((r < 0) != (b < 0)): r += b
		return ok(Value.VInt(r))
	if name == "abs":
		x := self.int_arg(name, args[0])?
		if x < 0: return ok(Value.VInt(sub_c(0, x)?))
		return ok(Value.VInt(x))
	if name == "min" or name == "max":
		var nums = List[Int]()
		for a in args:
			nums.append(self.int_arg(name, a)?)
		var best = nums[0]
		for x in nums:
			if name == "min" and x < best: best = x
			if name == "max" and x > best: best = x
		return ok(Value.VInt(best))
	if name == "list?":
		return ok(Value.VBool(self.to_vec(args[0]).is_some()))
	if name == "number?":
		match args[0]:
			VInt(_x): return ok(Value.VBool(true))
			_: return ok(Value.VBool(false))
	if name == "string?":
		match args[0]:
			VStr(_x): return ok(Value.VBool(true))
			_: return ok(Value.VBool(false))
	if name == "symbol?":
		match args[0]:
			VSym(_x): return ok(Value.VBool(true))
			_: return ok(Value.VBool(false))
	if name == "boolean?":
		match args[0]:
			VBool(_x): return ok(Value.VBool(true))
			_: return ok(Value.VBool(false))
	if name == "procedure?":
		match args[0]:
			VProc(_x): return ok(Value.VBool(true))
			VBuiltin(_x): return ok(Value.VBool(true))
			_: return ok(Value.VBool(false))
	if name == "set-car!" or name == "set-cdr!":
		p := pair_id(args[0])
		if p < 0: return error(self.terr(name, "pair", args[0]))
		if name == "set-car!":
			self.cars[p] = args[1]
		else:
			self.cdrs[p] = args[1]
		return ok(Value.VVoid)
	if name == "length":
		l := self.list_arg(name, args[0])?
		return ok(Value.VInt(l.length()))
	if name == "append":
		var result = args[n - 1]
		var i = n - 2
		var lists = List[List[Value]]()
		for k in 0..n - 1:
			lists.append(self.list_arg(name, args[k])?)
		while i >= 0:
			result = self.from_vec(lists[i], result)
			i -= 1
		return ok(result)
	if name == "reverse":
		l := self.list_arg(name, args[0])?
		var r = Value.VNil
		for x in l:
			r = self.cons(x, r)
		return ok(r)
	if name == "list-ref" or name == "list-tail":
		l := self.list_arg(name, args[0])?
		k := self.int_arg(name, args[1])?
		if name == "list-ref":
			if k < 0 or k >= l.length(): return fail("list-ref: index out of range")
			return ok(l[k])
		if k < 0 or k > l.length(): return fail("list-tail: index out of range")
		return ok(self.nth_tail(args[0], k))
	if name == "range":
		a := self.int_arg(name, args[0])?
		b := self.int_arg(name, args[1])?
		var items = List[Value]()
		var i = a
		while i < b:
			items.append(Value.VInt(i))
			i += 1
		return ok(self.from_vec(items, Value.VNil))
	if name == "assoc" or name == "member":
		l := self.list_arg(name, args[1])?
		var cur = args[1]
		for x in l:
			if name == "assoc":
				p := pair_id(x)
				if p < 0: return error(self.terr(name, "pair", x))
				if self.equal(self.cars[p], args[0]): return ok(x)
			else:
				if self.equal(x, args[0]): return ok(cur)
				cur = self.cdrs[pair_id(cur)]
		return ok(Value.VBool(false))
	if name == "map" or name == "for-each":
		self.proc_arg(name, args[0])?
		var lists = List[List[Value]]()
		for k in 1..n:
			lists.append(self.list_arg(name, args[k])?)
		var m = lists[0].length()
		for l in lists:
			if l.length() < m: m = l.length()
		var results = List[Value]()
		for i in 0..m:
			var cargs = List[Value]()
			for l in lists:
				cargs.append(l[i])
			r := self.call_proc(args[0], cargs)?
			results.append(r)
		if name == "for-each": return ok(Value.VVoid)
		return ok(self.from_vec(results, Value.VNil))
	if name == "filter":
		self.proc_arg(name, args[0])?
		l := self.list_arg(name, args[1])?
		var results = List[Value]()
		for x in l:
			var cargs = List[Value]()
			cargs.append(x)
			r := self.call_proc(args[0], cargs)?
			if truthy(r): results.append(x)
		return ok(self.from_vec(results, Value.VNil))
	if name == "fold" or name == "foldr":
		self.proc_arg(name, args[0])?
		l := self.list_arg(name, args[2])?
		var acc = args[1]
		if name == "fold":
			for x in l:
				var cargs = List[Value]()
				cargs.append(acc)
				cargs.append(x)
				acc = self.call_proc(args[0], cargs)?
		else:
			var i = l.length() - 1
			while i >= 0:
				var cargs = List[Value]()
				cargs.append(l[i])
				cargs.append(acc)
				acc = self.call_proc(args[0], cargs)?
				i -= 1
		return ok(acc)
	if name == "apply":
		self.proc_arg(name, args[0])?
		last := self.list_arg(name, args[n - 1])?
		var cargs = List[Value]()
		for k in 1..n - 1:
			cargs.append(args[k])
		for x in last:
			cargs.append(x)
		return self.call_proc(args[0], cargs)
	if name == "sort":
		self.proc_arg(name, args[1])?
		l := self.list_arg(name, args[0])?
		sorted := self.msort(l, args[1])?
		return ok(self.from_vec(sorted, Value.VNil))
	if name == "string-length":
		s := self.str_arg(name, args[0])?
		return ok(Value.VInt(s.length()))
	if name == "string-append":
		var strs = List[String]()
		for a in args:
			strs.append(self.str_arg(name, a)?)
		return ok(self.mk_str(strs.join("")))
	if name == "substring":
		s := self.str_arg(name, args[0])?
		a := self.int_arg(name, args[1])?
		b := self.int_arg(name, args[2])?
		if a < 0 or a > b or b > s.length(): return fail("substring: index out of range")
		return ok(self.mk_str(s.view(a, b)))
	if name == "string-ref":
		s := self.str_arg(name, args[0])?
		k := self.int_arg(name, args[1])?
		if k < 0 or k >= s.length(): return fail("string-ref: index out of range")
		return ok(self.mk_str(s.view(k, k + 1)))
	if name == "string=?" or name == "string<?":
		a := self.str_arg(name, args[0])?
		b := self.str_arg(name, args[1])?
		if name == "string=?": return ok(Value.VBool(a == b))
		return ok(Value.VBool(a < b))
	if name == "string-upcase" or name == "string-downcase":
		s := self.str_arg(name, args[0])?
		if name == "string-upcase": return ok(self.mk_str(s.upper()))
		return ok(self.mk_str(s.lower()))
	if name == "string->number":
		s := self.str_arg(name, args[0])?
		if not is_int_token(s): return ok(Value.VBool(false))
		if v := s.parse_int(): return ok(Value.VInt(v))
		return ok(Value.VBool(false))
	if name == "number->string":
		x := self.int_arg(name, args[0])?
		return ok(self.mk_str("{x}"))
	if name == "string->symbol":
		s := self.str_arg(name, args[0])?
		return ok(Value.VSym(self.intern(s)))
	if name == "symbol->string":
		match args[0]:
			VSym(id): return ok(self.mk_str(self.sym_names[id].clone()))
			_: return error(self.terr(name, "symbol", args[0]))
	if name == "string->list":
		s := self.str_arg(name, args[0])?
		var items = List[Value]()
		for i in 0..s.length():
			items.append(self.mk_str(s.view(i, i + 1)))
		return ok(self.from_vec(items, Value.VNil))
	if name == "list->string":
		l := self.list_arg(name, args[0])?
		var strs = List[String]()
		for x in l:
			strs.append(self.str_arg(name, x)?)
		return ok(self.mk_str(strs.join("")))
	if name == "string-join":
		l := self.list_arg(name, args[0])?
		var strs = List[String]()
		for x in l:
			strs.append(self.str_arg(name, x)?)
		sep := self.str_arg(name, args[1])?
		return ok(self.mk_str(strs.join(sep)))
	if name == "string-split":
		s := self.str_arg(name, args[0])?
		sep := self.str_arg(name, args[1])?
		if sep.length() != 1: return fail("string-split: separator must be one character")
		var items = List[Value]()
		for part in s.split(sep):
			items.append(self.mk_str(part))
		return ok(self.from_vec(items, Value.VNil))
	if name == "string-contains?":
		s := self.str_arg(name, args[0])?
		sub := self.str_arg(name, args[1])?
		return ok(Value.VBool(s.contains(sub)))
	if name == "display" or name == "write":
		self.out += self.show(args[0], name == "write")
		return ok(Value.VVoid)
	if name == "newline":
		self.out += "\n"
		return ok(Value.VVoid)
	if name == "void": return ok(Value.VVoid)
	if name == "error":
		msg := self.str_arg(name, args[0])?
		var s = msg
		for i in 1..n:
			s += " " + self.show(args[i], true)
		return fail(s)
	return fail("unimplemented builtin: {name}")

// ---------- reader ----------

fn Interp.byte(i: Int) Int: self.src.get(i).to_int()

fn Interp.at_end() Bool: self.pos >= self.src.length()

fn var Interp.skip_ws() Unit:
	while self.pos < self.src.length():
		c := self.byte(self.pos)
		if is_ws(c):
			self.pos += 1
		else if c == 59:
			while self.pos < self.src.length() and self.byte(self.pos) != 10:
				self.pos += 1
		else:
			return

fn var Interp.read_string() Value!:
	// self.pos is just after the opening quote
	var s = ""
	var run = self.pos
	while true:
		if self.pos >= self.src.length(): return fail("syntax error: unterminated string")
		c := self.byte(self.pos)
		if c == 34:
			s += self.text.view(run, self.pos)
			self.pos += 1
			return ok(self.mk_str(s))
		if c == 92:
			s += self.text.view(run, self.pos)
			if self.pos + 1 >= self.src.length(): return fail("syntax error: unterminated string")
			d := self.byte(self.pos + 1)
			if d == 110:
				s += "\n"
			else if d == 116:
				s += "\t"
			else if d == 92:
				s += "\\"
			else if d == 34:
				s += "\""
			else:
				return fail("syntax error: bad escape")
			self.pos += 2
			run = self.pos
		else:
			self.pos += 1
	return fail("unreachable")

fn Interp.dot_ahead() Bool:
	if self.byte(self.pos) != 46: return false
	return self.pos + 1 >= self.src.length() or is_delim(self.byte(self.pos + 1))

fn var Interp.read_list() Value!:
	// self.pos is just after '('
	var items = List[Value]()
	var tail = Value.VNil
	while true:
		self.skip_ws()
		if self.at_end(): return fail("syntax error: unexpected end of input")
		c := self.byte(self.pos)
		if c == 41:
			self.pos += 1
			return ok(self.from_vec(items, tail))
		if self.dot_ahead():
			if items.length() == 0: return fail("syntax error: bad dotted list")
			self.pos += 1
			self.skip_ws()
			if self.at_end(): return fail("syntax error: unexpected end of input")
			tail = self.read_form()?
			self.skip_ws()
			if self.at_end(): return fail("syntax error: unexpected end of input")
			if self.byte(self.pos) != 41: return fail("syntax error: bad dotted list")
			self.pos += 1
			return ok(self.from_vec(items, tail))
		items.append(self.read_form()?)
	return fail("unreachable")

fn var Interp.read_form() Value!:
	self.skip_ws()
	if self.at_end(): return fail("syntax error: unexpected end of input")
	c := self.byte(self.pos)
	if c == 41:
		self.pos += 1
		return fail("syntax error: unexpected )")
	if c == 40:
		self.pos += 1
		return self.read_list()
	if c == 39:
		self.pos += 1
		self.skip_ws()
		if self.at_end(): return fail("syntax error: unexpected end of input")
		d := self.read_form()?
		q := Value.VSym(self.intern("quote"))
		return ok(self.from_vec([q, d], Value.VNil))
	if c == 34:
		self.pos += 1
		return self.read_string()
	start := self.pos
	while self.pos < self.src.length() and not is_delim(self.byte(self.pos)):
		self.pos += 1
	tok := self.text.view(start, self.pos).clone()
	if tok == "#t": return ok(Value.VBool(true))
	if tok == "#f": return ok(Value.VBool(false))
	if tok.starts_with("#"): return fail("syntax error: bad token: {tok}")
	if is_int_token(tok):
		if v := tok.parse_int(): return ok(Value.VInt(v))
		return fail("syntax error: integer out of range")
	if tok == ".": return fail("syntax error: unexpected .")
	return ok(Value.VSym(self.intern(tok)))

// ---------- main ----------

fn var Interp.setup() Unit:
	self.frames.append(Frame(parent: -1, names: List[Int](), cells: List[Int]()))
	for nm in ["quote", "if", "define", "set!", "lambda", "begin", "let", "let*", "letrec", "cond", "and", "or", "when", "unless", "try"]:
		self.intern(nm)
	self.s_else = self.intern("else")
	self.s_lambda = self.intern("lambda")
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
	self.reg("zero?", 1, 1)
	self.reg("even?", 1, 1)
	self.reg("odd?", 1, 1)
	self.reg("not", 1, 1)
	self.reg("null?", 1, 1)
	self.reg("pair?", 1, 1)
	self.reg("list?", 1, 1)
	self.reg("number?", 1, 1)
	self.reg("string?", 1, 1)
	self.reg("symbol?", 1, 1)
	self.reg("boolean?", 1, 1)
	self.reg("procedure?", 1, 1)
	self.reg("eq?", 2, 2)
	self.reg("equal?", 2, 2)
	self.reg("cons", 2, 2)
	self.reg("car", 1, 1)
	self.reg("cdr", 1, 1)
	self.reg("cadr", 1, 1)
	self.reg("cddr", 1, 1)
	self.reg("caddr", 1, 1)
	self.reg("set-car!", 2, 2)
	self.reg("set-cdr!", 2, 2)
	self.reg("list", 0, -1)
	self.reg("length", 1, 1)
	self.reg("append", 0, -1)
	self.reg("reverse", 1, 1)
	self.reg("list-ref", 2, 2)
	self.reg("list-tail", 2, 2)
	self.reg("range", 2, 2)
	self.reg("assoc", 2, 2)
	self.reg("member", 2, 2)
	self.reg("map", 2, -1)
	self.reg("for-each", 2, -1)
	self.reg("filter", 2, 2)
	self.reg("fold", 3, 3)
	self.reg("foldr", 3, 3)
	self.reg("apply", 2, -1)
	self.reg("sort", 2, 2)
	self.reg("string-length", 1, 1)
	self.reg("string-append", 0, -1)
	self.reg("substring", 3, 3)
	self.reg("string-ref", 2, 2)
	self.reg("string=?", 2, 2)
	self.reg("string<?", 2, 2)
	self.reg("string-upcase", 1, 1)
	self.reg("string-downcase", 1, 1)
	self.reg("string->number", 1, 1)
	self.reg("number->string", 1, 1)
	self.reg("string->symbol", 1, 1)
	self.reg("symbol->string", 1, 1)
	self.reg("string->list", 1, 1)
	self.reg("list->string", 1, 1)
	self.reg("string-join", 2, 2)
	self.reg("string-split", 2, 2)
	self.reg("string-contains?", 2, 2)
	self.reg("display", 1, 1)
	self.reg("write", 1, 1)
	self.reg("newline", 0, 0)
	self.reg("void", 0, 0)
	self.reg("error", 1, -1)

fn var Interp.finish_error(msg: String) Unit:
	if self.out.length() > 0 and not self.out.ends_with("\n"):
		self.out += "\n"
	self.out += "error: {msg}\n"

fn var Interp.run() Unit:
	while true:
		self.skip_ws()
		if self.at_end(): return
		r := self.read_form()
		if form := r:
			rv := self.eval(form, 0)
			if rv.is_error():
				self.finish_error(rv.err().message)
				return
		else:
			self.finish_error(r.err().message)
			return

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var it = Interp(src: text.to_bytes(), text: text, strs: List[String](), sym_names: List[String](), sym_ids: Map[String, Int](), cars: List[Value](), cdrs: List[Value](), closures: List[Closure](), bnames: List[String](), bmin: List[Int](), bmax: List[Int](), frames: List[Frame](), cells: List[Value](), globals: Map[Int, Int]())
	it.setup()
	it.run()
	print(it.out, end: "")
