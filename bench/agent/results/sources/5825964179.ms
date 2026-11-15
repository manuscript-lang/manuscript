import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Req:
	name: String
	lo: Int
	hi: Int

type Release:
	ver: Int
	deps: List[Req]

type Range:
	lo: Int
	hi: Int

type State:
	pkgs: Map[String, List[Release]] = Map[String, List[Release]]()
	chosen: Map[String, Int] = Map[String, Int]()
	unknown: String = ""

M := 1000000
INF := 9000000000000000000

fn is_digit(c: String) Bool: c >= "0" and c <= "9"

fn is_name(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not (is_digit(c) or (c >= "a" and c <= "z") or c == "-"): return false
	return true

fn parse_num(s: String) Int:
	n := s.length()
	if n < 1 or n > 6: return -1
	for c in s.chars():
		if not is_digit(c): return -1
	if n > 1 and s.starts_with("0"): return -1
	return s.parse_int().get(-1)

fn parse_ver(s: String) Int:
	parts := s.split(".")
	if parts.length() != 3: return -1
	a := parse_num(parts.get(0, ""))
	b := parse_num(parts.get(1, ""))
	c := parse_num(parts.get(2, ""))
	if a < 0 or b < 0 or c < 0: return -1
	return a * M * M + b * M + c

fn fmt_ver(v: Int) String:
	a := v / (M * M)
	b := (v / M) % M
	c := v % M
	return "{a}.{b}.{c}"

fn parse_clause(s: String) Range?:
	if s == "*": return Range(0, INF)
	if s.starts_with(">="):
		v := parse_ver(s.slice(2, s.length()).get(""))
		if v < 0: return none
		return Range(v, INF)
	if s.starts_with("<="):
		v := parse_ver(s.slice(2, s.length()).get(""))
		if v < 0: return none
		return Range(0, v + 1)
	if s.length() == 0: return none
	rest := s.slice(1, s.length()).get("")
	first := s.slice(0, 1).get("")
	if first == ">":
		v := parse_ver(rest)
		if v < 0: return none
		return Range(v + 1, INF)
	if first == "<":
		v := parse_ver(rest)
		if v < 0: return none
		return Range(0, v)
	if first == "=":
		v := parse_ver(rest)
		if v < 0: return none
		return Range(v, v + 1)
	if first == "^":
		v := parse_ver(rest)
		if v < 0: return none
		a := v / (M * M)
		b := (v / M) % M
		if a > 0: return Range(v, (a + 1) * M * M)
		if b > 0: return Range(v, (b + 1) * M)
		return Range(v, v + 1)
	if first == "~":
		v := parse_ver(rest)
		if v < 0: return none
		a := v / (M * M)
		b := (v / M) % M
		return Range(v, a * M * M + (b + 1) * M)
	v := parse_ver(s)
	if v < 0: return none
	return Range(v, v + 1)

fn parse_constraint(s: String) Range?:
	var lo = 0
	var hi = INF
	for part in s.split(","):
		if r := parse_clause(part):
			if r.lo > lo: lo = r.lo
			if r.hi < hi: hi = r.hi
		else:
			return none
	return Range(lo, hi)

fn var State.solve(pending: List[Req]) Int:
	if pending.length() == 0: return 1
	first := pending.get(0, Req("", 0, 0))
	n := first.name.clone()
	lo := first.lo
	hi := first.hi
	var rest = List[Req]()
	for i in 1..pending.length():
		rest.append(pending.get(i, Req("", 0, 0)).clone())
	if cv := self.chosen.get(n):
		if cv >= lo and cv < hi:
			return self.solve(rest)
		return 0
	var nrel = 0
	if rels := self.pkgs.get(n):
		nrel = rels.length()
	else:
		self.unknown = n.clone()
		return 2
	for i in 0..nrel:
		var ver = -1
		var np = List[Req]()
		if rels := self.pkgs.get(n):
			rel := rels.get(i, Release(-1, []))
			ver = rel.ver
			if ver < lo or ver >= hi: continue
			np.extend(rel.deps)
		np.extend(rest)
		self.chosen[n.clone()] = ver
		r := self.solve(np)
		if r != 0: return r
		self.chosen.remove(n.clone())
	return 0

fn var State.add(tokens: List[String]) String:
	name := tokens.get(1, "")
	if not is_name(name): return "error: bad name '{name}'"
	vs := tokens.get(2, "")
	ver := parse_ver(vs)
	if ver < 0: return "error: bad version '{vs}'"
	var deps = List[Req]()
	var seen = Set[String]()
	for i in 3..tokens.length():
		tok := tokens.get(i, "")
		idx := tok.index_of(":")
		if idx.is_none(): return "error: bad dependency '{tok}'"
		k := idx.get(0)
		dn := tok.slice(0, k).get("")
		ct := tok.slice(k + 1, tok.length()).get("")
		if not is_name(dn): return "error: bad dependency '{tok}'"
		rg := parse_constraint(ct)
		if rg.is_none(): return "error: bad constraint '{ct}'"
		if seen.contains(dn): return "error: duplicate dependency '{dn}'"
		seen.add(dn.clone())
		r := rg.get(Range(0, 0))
		deps.append(Req(dn.clone(), r.lo, r.hi))
	deps.sort(fn(a: Req, b: Req) Int: if a.name < b.name: -1 else: (if a.name > b.name: 1 else: 0))
	if rels := self.pkgs.get(name):
		for r in rels:
			if r.ver == ver: return "error: duplicate {name} {vs}"
	if not self.pkgs.contains(name):
		self.pkgs[name.clone()] = List[Release]()
	if var rels = self.pkgs[name]?:
		rels.append(Release(ver, deps))
		rels.sort(fn(a: Release, b: Release) Int: if a.ver > b.ver: -1 else: (if a.ver < b.ver: 1 else: 0))
	return "ok"

fn var State.run(line: String) Unit:
	t := line.fields()
	if t.length() == 0: return
	cmd := t.get(0, "")
	if cmd == "pkg":
		if t.length() < 3:
			print("error: usage")
			return
		print(self.add(t))
	else if cmd == "list":
		if t.length() != 2:
			print("error: usage")
			return
		name := t.get(1, "")
		if rels := self.pkgs.get(name):
			var vs = List[String]()
			var i = rels.length() - 1
			while i >= 0:
				vs.append(fmt_ver(rels.get(i, Release(0, [])).ver))
				i -= 1
			print("{name}: {vs.join(" ")}")
		else:
			print("error: unknown package {name}")
	else if cmd == "resolve":
		if t.length() != 3:
			print("error: usage")
			return
		name := t.get(1, "")
		ct := t.get(2, "")
		rg := parse_constraint(ct)
		if rg.is_none():
			print("error: bad constraint '{ct}'")
			return
		r := rg.get(Range(0, 0))
		self.chosen = Map[String, Int]()
		self.unknown = ""
		res := self.solve([Req(name.clone(), r.lo, r.hi)])
		if res == 2:
			print("error: unknown package {self.unknown}")
		else if res == 0:
			print("error: cannot resolve {name} {ct}")
		else:
			var names = List[String]()
			for e in self.chosen.entries():
				names.append(e.key.clone())
			names.sort()
			print("resolved {names.length()}")
			for nm in names:
				print("{nm} {fmt_ver(self.chosen.get_or(nm, 0))}")
	else:
		print("error: unknown command")

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var st = State()
	for line in lines(stdin()):
		st.run(line)
