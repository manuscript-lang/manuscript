import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Dep:
	name: String
	cons: List[Int]

type Release:
	ver: Int
	deps: List[Dep]

type State:
	pkgs: Map[String, List[Release]]
	chosen: Map[String, Int]
	unknown: String = ""

fn mk_dep(d: Dep) Dep:
	return Dep(d.name.clone(), d.cons.clone())

fn is_digits(s: String) Bool:
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn valid_name(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "abcdefghijklmnopqrstuvwxyz0123456789-".contains(c): return false
	return true

fn parse_version(s: String) Int?:
	parts := s.split(".")
	if parts.length() != 3: return none
	var v = 0
	for p in parts:
		if p.length() < 1 or p.length() > 6: return none
		if not is_digits(p): return none
		if p.length() > 1 and p.starts_with("0"): return none
		n := p.parse_int().get(0)
		v = v * 1000000 + n
	return v

fn rest_of(s: String, k: Int) String:
	return s.slice(k, s.length()).get("")

fn fmt_version(v: Int) String:
	return "{v / 1000000000000}.{(v / 1000000) % 1000000}.{v % 1000000}"

fn parse_clause(c: String, var out: List[Int]) Bool:
	big := 4000000000000000000
	if c == "*":
		out.append(0)
		out.append(big)
		return true
	if c.length() == 0: return false
	var op = ""
	if c.starts_with(">="): op = ">="
	else if c.starts_with("<="): op = "<="
	else if c.starts_with(">"): op = ">"
	else if c.starts_with("<"): op = "<"
	else if c.starts_with("="): op = "="
	else if c.starts_with("^"): op = "^"
	else if c.starts_with("~"): op = "~"
	body := rest_of(c, op.length())
	vo := parse_version(body)
	if vo.is_none(): return false
	v := vo.get(0)
	var lo = 0
	var hi = big
	if op == "" or op == "=":
		lo = v
		hi = v + 1
	else if op == ">":
		lo = v + 1
	else if op == ">=":
		lo = v
	else if op == "<":
		hi = v
	else if op == "<=":
		hi = v + 1
	else if op == "^":
		lo = v
		major := v / 1000000000000
		minor := (v / 1000000) % 1000000
		if major > 0: hi = (major + 1) * 1000000000000
		else if minor > 0: hi = (minor + 1) * 1000000
		else: hi = v + 1
	else:
		lo = v
		minor := v / 1000000
		hi = (minor + 1) * 1000000
	out.append(lo)
	out.append(hi)
	return true

fn parse_constraint(s: String) List[Int]?:
	var out = List[Int]()
	for c in s.split(","):
		if not parse_clause(c, var out): return none
	return out

fn satisfies(v: Int, cons: List[Int]) Bool:
	var i = 0
	while i < cons.length():
		if v < cons.get(i, 0) or v >= cons.get(i + 1, 0): return false
		i += 2
	return true

fn solve(var st: State, pending: List[Dep]) Bool:
	if pending.length() == 0: return true
	first := pending.get(0, Dep("", [])).name.clone()
	fcons := pending.get(0, Dep("", [])).cons.clone()
	if st.chosen.contains(first):
		if satisfies(st.chosen.get_or(first, 0), fcons):
			var rest = List[Dep]()
			for i in 1..pending.length():
				rest.append(mk_dep(pending.get(i, Dep("", []))))
			return solve(var st, rest)
		return false
	if not st.pkgs.contains(first):
		st.unknown = first.clone()
		return false
	rels := st.pkgs[first].clone()
	if true:
		for r in rels:
			if not satisfies(r.ver, fcons): continue
			st.chosen[first.clone()] = r.ver
			var np = List[Dep]()
			for d in r.deps:
				np.append(mk_dep(d))
			for i in 1..pending.length():
				np.append(mk_dep(pending.get(i, Dep("", []))))
			if solve(var st, np): return true
			if st.unknown.length() > 0: return false
			st.chosen.remove(first.clone())

	return false

// ms: allow_effect std.console.write
fn cmd_pkg(var st: State, t: List[String]) Unit:
	if t.length() < 3:
		print("error: usage")
		return
	name := t.get(1, "")
	if not valid_name(name):
		print("error: bad name '{name}'")
		return
	vo := parse_version(t.get(2, ""))
	if vo.is_none():
		print("error: bad version '{t.get(2, "")}'")
		return
	var deps = List[Dep]()
	var seen = Set[String]()
	for i in 3..t.length():
		tok := t.get(i, "")
		ci := tok.find_char(fn c: c == ":")
		if ci.is_none():
			print("error: bad dependency '{tok}'")
			return
		k := ci.get(0)
		dn := tok.slice(0, k).get("")
		cs := rest_of(tok, k + 1)
		if not valid_name(dn):
			print("error: bad dependency '{tok}'")
			return
		co := parse_constraint(cs)
		if co.is_none():
			print("error: bad constraint '{cs}'")
			return
		if seen.contains(dn):
			print("error: duplicate dependency '{dn}'")
			return
		seen.add(dn.clone())
		deps.append(Dep(dn, co.get([])))
	v := vo.get(0)
	if st.pkgs.contains(name):
		if true:
			for r in st.pkgs[name]:
				if r.ver == v:
					print("error: duplicate {name} {t.get(2, "")}")
					return
	deps.sort(fn(a: Dep, b: Dep) Int: if a.name < b.name: -1 else: (if a.name > b.name: 1 else: 0))
	if not st.pkgs.contains(name):
		st.pkgs[name.clone()] = List[Release]()
	st.pkgs[name].append(Release(v, deps))
	st.pkgs[name].sort(fn(a: Release, b: Release) Int: if a.ver > b.ver: -1 else: (if a.ver < b.ver: 1 else: 0))
	print("ok")

fn main() Unit!:
	var st = State(Map[String, List[Release]](), Map[String, Int]())
	for line in lines(stdin()):
		t := line.fields()
		if t.length() == 0: continue
		c := t.get(0, "")
		if c == "pkg":
			cmd_pkg(var st, t)
		else if c == "list":
			if t.length() != 2:
				print("error: usage")
			else if not st.pkgs.contains(t.get(1, "")):
				print("error: unknown package {t.get(1, "")}")
			else:
				var vs = List[String]()
				if true:
					for r in st.pkgs[t.get(1, "")]:
						vs.append(fmt_version(r.ver))
				vs.reverse()
				print("{t.get(1, "")}: {vs.join(" ")}")
		else if c == "resolve":
			if t.length() != 3:
				print("error: usage")
			else:
				co := parse_constraint(t.get(2, ""))
				if co.is_none():
					print("error: bad constraint '{t.get(2, "")}'")
				else:
					st.chosen = Map[String, Int]()
					st.unknown = ""
					ok_ := solve(var st, [Dep(t.get(1, ""), co.get([]))])
					if ok_:
						var names = List[String]()
						for e in st.chosen.entries():
							names.append(e.key.clone())
						names.sort()
						print("resolved {names.length()}")
						for n in names:
							print("{n} {fmt_version(st.chosen.get_or(n, 0))}")
					else if st.unknown.length() > 0:
						print("error: unknown package {st.unknown}")
					else:
						print("error: cannot resolve {t.get(1, "")} {t.get(2, "")}")
		else:
			print("error: unknown command")
