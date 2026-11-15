import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

M: Int := 1000000
INF: Int := 4000000000000000000

type Req:
	name: String
	lo: Int
	hi: Int

type Release:
	key: Int
	text: String
	deps: List[Req]

type State:
	pkgs: Map[String, List[Release]]
	chosen: Map[String, Int]
	unknown: String = ""

fn is_name(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-"
		if not ok: return false
	return true

fn parse_ver(s: String) Int:
	parts := s.split(".", none)
	if parts.length() != 3: return -1
	var key = 0
	for p in parts:
		n := p.length()
		if n < 1 or n > 6: return -1
		for c in p.chars():
			if c < "0" or c > "9": return -1
		if n > 1 and p.starts_with("0"): return -1
		key = key * M + p.parse_int().get(0)
	return key

fn bump_minor(key: Int) Int:
	return (key / (M * M) * M + (key / M) % M + 1) * M

fn bump_major(key: Int) Int:
	return (key / (M * M) + 1) * M * M

fn bad() Req: Req("", -1, -1)

fn clause(s: String) Req:
	if s == "*": return Req("", 0, INF)
	var op = ""
	if s.starts_with(">=") or s.starts_with("<="):
		op = s.slice(0, 2).get("")
	else if s.length() > 0 and (s.starts_with(">") or s.starts_with("<") or s.starts_with("=") or s.starts_with("^") or s.starts_with("~")):
		op = s.slice(0, 1).get("")
	v := parse_ver(s.slice(op.length(), s.length()).get(""))
	if v < 0: return bad()
	if op == ">=": return Req("", v, INF)
	if op == "<=": return Req("", 0, v + 1)
	if op == ">": return Req("", v + 1, INF)
	if op == "<": return Req("", 0, v)
	if op == "" or op == "=": return Req("", v, v + 1)
	if op == "~": return Req("", v, bump_minor(v))
	maj := v / (M * M)
	min := (v / M) % M
	if maj > 0: return Req("", v, bump_major(v))
	if min > 0: return Req("", v, bump_minor(v))
	return Req("", v, v + 1)

fn parse_cons(s: String) Req:
	var lo = 0
	var hi = INF
	for part in s.split(",", none):
		c := clause(part)
		if c.lo < 0: return bad()
		if c.lo > lo: lo = c.lo
		if c.hi < hi: hi = c.hi
	return Req("", lo, hi)

fn var State.solve(pending: List[Req]) Bool:
	if pending.length() == 0: return true
	first := pending.get(0, Req("", 0, 0))
	rest_start := 1
	if c := self.chosen.get(first.name):
		if c >= first.lo and c < first.hi:
			return self.solve(tail(pending, rest_start))
		return false
	rels := self.pkgs.get(first.name)
	if rels.is_none():
		self.unknown = first.name.clone()
		return false
	rl := rels.get(List[Release]())
	for r in rl:
		if r.key < first.lo or r.key >= first.hi: continue
		self.chosen[first.name.clone()] = r.key
		var next = List[Req]()
		for d in r.deps:
			next.append(Req(d.name.clone(), d.lo, d.hi))
		for i in 1..pending.length():
			p := pending.get(i, first)
			next.append(Req(p.name.clone(), p.lo, p.hi))
		if self.solve(next): return true
		if self.unknown.length() > 0: return false
		self.chosen.remove(first.name.clone())
	return false

fn tail(xs: List[Req], from: Int) List[Req]:
	var out = List[Req]()
	for i in from..xs.length():
		p := xs.get(i, Req("", 0, 0))
		out.append(Req(p.name.clone(), p.lo, p.hi))
	return out

fn dflt() Release: Release(0, "", [])

fn fmt(key: Int) String:
	return "{key / (M * M)}.{(key / M) % M}.{key % M}"

fn cmd_pkg(toks: List[String], var st: State) String:
	if toks.length() < 3: return "error: usage"
	name := toks.get(1, "")
	vs := toks.get(2, "")
	if not is_name(name): return "error: bad name '{name}'"
	k := parse_ver(vs)
	if k < 0: return "error: bad version '{vs}'"
	var deps = List[Req]()
	var seen = Set[String]()
	for i in 3..toks.length():
		t := toks.get(i, "")
		ci := t.index_of(":")
		if ci.is_none(): return "error: bad dependency '{t}'"
		idx := ci.get(0)
		dn := t.slice(0, idx).get("")
		ct := t.slice(idx + 1, t.length()).get("")
		if not is_name(dn): return "error: bad dependency '{t}'"
		r := parse_cons(ct)
		if r.lo < 0: return "error: bad constraint '{ct}'"
		if seen.contains(dn): return "error: duplicate dependency '{dn}'"
		seen.add(dn.clone())
		deps.append(Req(dn.clone(), r.lo, r.hi))
	existing := st.pkgs.get_or(name, List[Release]())
	for r in existing:
		if r.key == k: return "error: duplicate {name} {vs}"
	deps.sort(fn a, b: a.name.compare(b.name))
	var list = existing.clone()
	rel := Release(k, fmt(k), deps)
	var pos = list.length()
	for i in 0..list.length():
		if list.get(i, dflt()).key < k:
			pos = i
			break
	var out = List[Release]()
	for i in 0..pos:
		out.append(list.get(i, dflt()))
	out.append(rel)
	for i in pos..list.length():
		out.append(list.get(i, dflt()))
	st.pkgs[name.clone()] = out
	return "ok"

fn main() Void!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	var st = State(Map[String, List[Release]](), Map[String, Int]())
	var outl = List[String]()
	for line in text.lines():
		toks := line.fields()
		if toks.length() == 0: continue
		cmd := toks.get(0, "")
		args := tail_s(toks)
		if cmd == "pkg":
			outl.append(cmd_pkg(toks, var st))
		else if cmd == "list":
			if args.length() != 1:
				outl.append("error: usage")
			else:
				n := args.get(0, "")
				rs := st.pkgs.get(n)
				if rs.is_none():
					outl.append("error: unknown package {n}")
				else:
					vals := rs.get(List[Release]())
					var parts = List[String]()
					var i = vals.length()
					while i > 0:
						i -= 1
						parts.append(vals.get(i, vals.get(0, Release(0, "", []))).text.clone())
					outl.append("{n}: {parts.join(" ")}")
		else if cmd == "resolve":
			if args.length() != 2:
				outl.append("error: usage")
			else:
				n := args.get(0, "")
				ct := args.get(1, "")
				r := parse_cons(ct)
				if r.lo < 0:
					outl.append("error: bad constraint '{ct}'")
				else:
					st.chosen = Map[String, Int]()
					st.unknown = ""
					if st.solve([Req(n.clone(), r.lo, r.hi)]):
						var ks = st.chosen.keys().clone()
						ks.sort(fn a, b: a.compare(b))
						outl.append("resolved {ks.length()}")
						for k in ks:
							outl.append("{k} {fmt(st.chosen.get_or(k, 0))}")
					else if st.unknown.length() > 0:
						outl.append("error: unknown package {st.unknown}")
					else:
						outl.append("error: cannot resolve {n} {ct}")
		else:
			outl.append("error: unknown command")
	for l in outl:
		print(l)

fn tail_s(xs: List[String]) List[String]:
	var out = List[String]()
	for i in 1..xs.length():
		out.append(xs.get(i, "").clone())
	return out
