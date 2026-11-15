import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

type Req:
	name: String
	lo: Int
	hi: Int

type Rel:
	name: String
	ver: Int
	deps: List[Req]

type State:
	chosen: Map[String, Int] = Map[String, Int]()
	unknown: String = ""
	stopped: Bool = false

type Range:
	lo: Int
	hi: Int

type Ver:
	v: Int

fn enc(a: Int, b: Int, c: Int) Int: a * 1000000000000 + b * 1000000 + c

fn all_in(s: String, set: String) Bool:
	for i in 0..s.length():
		ch := s.slice(i, i + 1).get("")
		if not set.contains(ch): return false
	return true

fn is_name(s: String) Bool:
	return s.length() > 0 and all_in(s, "abcdefghijklmnopqrstuvwxyz0123456789-")

fn parse_ver(s: String) Int?:
	parts := s.split(".")
	if parts.length() != 3: return none
	var nums = List[Int]()
	for p in parts:
		if p.length() < 1 or p.length() > 6: return none
		if not all_in(p, "0123456789"): return none
		if p.length() > 1 and p.starts_with("0"): return none
		n := p.parse_int().get(-1)
		if n < 0: return none
		nums.append(n)
	return enc(nums.get(0, 0), nums.get(1, 0), nums.get(2, 0))

fn parse_clause(c: String) Range?:
	maxv := 999999999999999999
	if c == "*": return Range(0, maxv)
	var op = ""
	for o in [">=", "<=", ">", "<", "=", "^", "~"]:
		if op == "" and c.starts_with(o): op = o.clone()
	rest := c.slice(op.length(), c.length()).get("")
	vo := parse_ver(rest)
	if vo.is_none(): return none
	v := vo.get(0)
	major := v / 1000000000000
	minor := (v / 1000000) % 1000000
	if op == "" or op == "=": return Range(v, v)
	if op == ">": return Range(v + 1, maxv)
	if op == ">=": return Range(v, maxv)
	if op == "<": return Range(0, v - 1)
	if op == "<=": return Range(0, v)
	if op == "~": return Range(v, enc(major, minor + 1, 0) - 1)
	if major > 0: return Range(v, enc(major + 1, 0, 0) - 1)
	if minor > 0: return Range(v, enc(0, minor + 1, 0) - 1)
	return Range(v, v)

fn parse_constraint(s: String) Range?:
	var lo = 0
	var hi = 999999999999999999
	for c in s.split(","):
		ro := parse_clause(c)
		if ro.is_none(): return none
		r := ro.get(Range(0, 0))
		if r.lo > lo: lo = r.lo
		if r.hi < hi: hi = r.hi
	return Range(lo, hi)

fn show(v: Int) String:
	return "{v / 1000000000000}.{(v / 1000000) % 1000000}.{v % 1000000}"

fn has_pkg(rels: List[Rel], name: String) Bool:
	for r in rels:
		if r.name == name: return true
	return false

fn clone_req(r: Req) Req: Req(r.name.clone(), r.lo, r.hi)

fn solve(rels: List[Rel], var st: State, pending: List[Req]) Bool:
	if pending.length() == 0: return true
	first := pending.get(0, Req("", 0, 0))
	if st.chosen.get(first.name).is_some():
		cv := st.chosen.get_or(first.name, 0)
		if cv >= first.lo and cv <= first.hi:
			return solve(rels, var st, rest_of(pending, 1))
		return false
	if not has_pkg(rels, first.name):
		st.unknown = first.name.clone()
		st.stopped = true
		return false
	var cands = List[Int]()
	for r in rels:
		if r.name == first.name and r.ver >= first.lo and r.ver <= first.hi:
			cands.append(r.ver)
	cands.sort(fn(a: Int, b: Int) Int: b - a)
	for cv in cands:
		st.chosen[first.name.clone()] = cv
		var np = List[Req]()
		for r in rels:
			if r.name == first.name and r.ver == cv:
				for d in r.deps:
					np.append(clone_req(d))
		for i in 1..pending.length():
			np.append(clone_req(pending.get(i, first)))
		if solve(rels, var st, np): return true
		if st.stopped: return false
		st.chosen.remove(first.name.clone())
	return false

fn rest_of(p: List[Req], from: Int) List[Req]:
	var out = List[Req]()
	for i in from..p.length():
		out.append(clone_req(p.get(i, Req("", 0, 0))))
	return out

fn handle(line: String, var rels: List[Rel], var out: List[String]) Unit:
	t := line.fields()
	if t.length() == 0: return
	cmd := t.get(0, "")
	if cmd == "pkg":
		if t.length() < 3:
			out.append("error: usage")
			return
		name := t.get(1, "")
		vs := t.get(2, "")
		if not is_name(name):
			out.append("error: bad name '{name}'")
			return
		ver := parse_ver(vs)
		if ver.is_none():
			out.append("error: bad version '{vs}'")
			return
		v := ver.get(0)
		var deps = List[Req]()
		var seen = Set[String]()
		for i in 3..t.length():
			tok := t.get(i, "")
			ci := tok.index_of(":")
			if ci.is_none():
				out.append("error: bad dependency '{tok}'")
				return
			k := ci.get(0)
			dn := tok.slice(0, k).get("")
			ctext := tok.slice(k + 1, tok.length()).get("")
			if not is_name(dn):
				out.append("error: bad dependency '{tok}'")
				return
			rg := parse_constraint(ctext)
			if rg.is_none():
				out.append("error: bad constraint '{ctext}'")
				return
			if seen.contains(dn):
				out.append("error: duplicate dependency '{dn}'")
				return
			seen.add(dn.clone())
			r := rg.get(Range(0, 0))
			deps.append(Req(dn.clone(), r.lo, r.hi))
		for r in rels:
			if r.name == name and r.ver == v:
				out.append("error: duplicate {name} {vs}")
				return
		deps.sort(fn(a: Req, b: Req) Int: if a.name < b.name: -1 else: if a.name > b.name: 1 else: 0)
		rels.append(Rel(name.clone(), v, deps))
		out.append("ok")
		return
	if cmd == "list":
		if t.length() != 2:
			out.append("error: usage")
			return
		name := t.get(1, "")
		var vers = List[Int]()
		for r in rels:
			if r.name == name: vers.append(r.ver)
		if vers.length() == 0:
			out.append("error: unknown package {name}")
			return
		vers.sort()
		var parts = List[String]()
		for v in vers: parts.append(show(v))
		out.append("{name}: {parts.join(" ")}")
		return
	if cmd == "resolve":
		if t.length() != 3:
			out.append("error: usage")
			return
		name := t.get(1, "")
		ct := t.get(2, "")
		rg := parse_constraint(ct)
		if rg.is_none():
			out.append("error: bad constraint '{ct}'")
			return
		r := rg.get(Range(0, 0))
		var st = State()
		ok := solve(rels, var st, [Req(name.clone(), r.lo, r.hi)])
		if ok:
			var names = List[String]()
			for e in st.chosen.entries(): names.append(e.key.clone())
			names.sort()
			out.append("resolved {names.length()}")
			for n in names:
				out.append("{n} {show(st.chosen.get_or(n, 0))}")
		else if st.stopped:
			out.append("error: unknown package {st.unknown}")
		else:
			out.append("error: cannot resolve {name} {ct}")
		return
	out.append("error: unknown command")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var rels = List[Rel]()
	var out = List[String]()
	for line in lines(stdin()):
		handle(line, var rels, var out)
	for o in out: print(o)
