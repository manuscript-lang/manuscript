import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import fnv1a64 from "@std/crypto/hash.ms"

type Commit:
	id: String
	parents: List[Int]
	msg: String
	tree: Map[String, String]

type Repo:
	commits: List[Commit] = []
	ids: Map[String, Int] = Map[String, Int]()
	branches: Map[String, Int] = Map[String, Int]()
	tags: Map[String, Int] = Map[String, Int]()
	detached: Bool = false
	hbranch: String = "main"
	hcommit: Int = -1
	index: Map[String, String] = Map[String, String]()
	work: Map[String, String] = Map[String, String]()
	merging: Bool = false
	mbranch: String = ""
	mother: Int = -1
	conflicts: Set[String] = Set[String]()

// ms: allow_effect std.console.write
fn out(s: String) Unit:
	print(s)

fn fail(msg: String) Unit!:
	return error(Error(msg))

fn hash_of(s: String) String:
	return fnv1a64(s.as_bytes()).to_string_radix(16).pad_start(16, "0")

fn short(id: String) String:
	if r := id.slice(0, 7):
		return r.clone()
	return id.clone()

fn sorted_keys(m: Map[String, String]) List[String]:
	var ks = List[String]()
	for k in m.keys(): ks.append(k.clone())
	ks.sort()
	return ks

fn tree_hash(t: Map[String, String]) String:
	var s = ""
	for k in sorted_keys(t):
		s += "{k} {hash_of(t.get_or(k, ""))}\n"
	return hash_of(s)

fn tree_eq(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for e in a.entries():
		if v := b.get(e.key):
			if v != e.value: return false
		else:
			return false
	return true

fn lines_of(content: String) List[String]:
	var res = List[String]()
	if content == "": return res
	parts := content.split("\n")
	n := parts.length()
	for i in 0..(n - 1):
		res.append(parts[i].clone())
	return res

fn content_of(lines: List[String]) String:
	var s = ""
	for l in lines:
		s += l
		s += "\n"
	return s

fn range_lines(xs: List[String], s: Int, e: Int) List[String]:
	var res = List[String]()
	var i = s
	while i < e:
		res.append(xs[i].clone())
		i += 1
	return res

fn match_pairs(a: List[String], b: List[String]) List[Int]:
	n := a.length()
	m := b.length()
	w := m + 1
	var l = List[Int]()
	for _k in 0..((n + 1) * w):
		l.append(0)
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a[i] == b[j]:
				l[i * w + j] = 1 + l[(i + 1) * w + j + 1]
			else:
				x := l[(i + 1) * w + j]
				y := l[i * w + j + 1]
				l[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	var res = List[Int]()
	for _k in 0..n:
		res.append(-1)
	i = 0
	var j = 0
	while i < n and j < m:
		if a[i] == b[j]:
			res[i] = j
			i += 1
			j += 1
		else if l[(i + 1) * w + j] >= l[i * w + j + 1]:
			i += 1
		else:
			j += 1
	return res

fn line_diff(a: List[String], b: List[String]) List[String]:
	mt := match_pairs(a, b)
	var res = List[String]()
	var pi = 0
	var pj = 0
	for i in 0..a.length():
		j := mt[i]
		if j < 0: continue
		while pi < i:
			res.append("- {a[pi]}")
			pi += 1
		while pj < j:
			res.append("+ {b[pj]}")
			pj += 1
		res.append("  {a[i]}")
		pi = i + 1
		pj = j + 1
	while pi < a.length():
		res.append("- {a[pi]}")
		pi += 1
	while pj < b.length():
		res.append("+ {b[pj]}")
		pj += 1
	return res

// returns (merged lines, conflict?)
type Merged:
	lines: List[String]
	conflict: Bool

fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) Merged:
	mo := match_pairs(base, ours)
	mt := match_pairs(base, theirs)
	var res = List[String]()
	var conflict = false
	var pb = -1
	var po = -1
	var pt = -1
	n := base.length()
	for bi in 0..(n + 1):
		final := bi == n
		var oi = ours.length()
		var ti = theirs.length()
		if not final:
			oi = mo[bi]
			ti = mt[bi]
			if oi < 0 or ti < 0: continue
		bc := range_lines(base, pb + 1, bi)
		oc := range_lines(ours, po + 1, oi)
		tc := range_lines(theirs, pt + 1, ti)
		if oc == bc:
			for x in tc: res.append(x.clone())
		else if tc == bc:
			for x in oc: res.append(x.clone())
		else if oc == tc:
			for x in oc: res.append(x.clone())
		else:
			conflict = true
			res.append("<<<<<<< HEAD")
			for x in oc: res.append(x.clone())
			res.append("=======")
			for x in tc: res.append(x.clone())
			res.append(">>>>>>> {branch}")
		if not final:
			res.append(base[bi].clone())
		pb = bi
		po = oi
		pt = ti
	return Merged(res, conflict)

fn valid_name(name: String) Bool:
	cs := name.chars()
	if cs.length() == 0: return false
	for i in 0..cs.length():
		c := cs[i]
		ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "." or c == "_" or c == "/" or (i > 0 and c == "-")
		if not ok: return false
	return true

fn is_digits(s: String) Bool:
	if s == "": return false
	for c in s.chars():
		if not (c >= "0" and c <= "9"): return false
	return true

fn is_hex(s: String) Bool:
	for c in s.chars():
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")): return false
	return true

fn Repo.cur() Int:
	if self.detached: return self.hcommit
	return self.branches.get_or(self.hbranch, -1)

fn Repo.label() String:
	if self.detached: return "detached"
	return self.hbranch.clone()

fn Repo.tree_of(c: Int) Map[String, String]:
	if c < 0: return Map[String, String]()
	return self.commits[c].tree.clone()

fn Repo.sid(c: Int) String:
	return short(self.commits[c].id)

fn Repo.line(c: Int) String:
	return "{self.sid(c)} {self.commits[c].msg}"

fn Repo.resolve(r: String) Int!:
	unk := "unknown revision '{r}'"
	parts := r.split("~")
	if parts.length() > 2: return error(Error(unk))
	base := parts[0].clone()
	var steps = 0
	if parts.length() == 2:
		if not is_digits(parts[1]): return error(Error(unk))
		if n := parts[1].parse_int():
			steps = n
		else:
			return error(Error(unk))
	var c = -1
	if base == "HEAD":
		c = self.cur()
		if c < 0: return error(Error(unk))
	else:
		b := self.branches.get_or(base, -1)
		if b >= 0:
			c = b
		else if self.tags.contains(base):
			c = self.tags.get_or(base, -1)
		else:
			if base.length() >= 4 and is_hex(base):
				var found = 0
				for e in self.ids.entries():
					if e.key.starts_with(base):
						found += 1
						c = e.value
				if found > 1: return error(Error("ambiguous revision '{r}'"))
				if found == 0: return error(Error(unk))
			else:
				return error(Error(unk))
	var k = 0
	while k < steps:
		if self.commits[c].parents.length() == 0: return error(Error(unk))
		c = self.commits[c].parents[0]
		k += 1
	return ok(c)

fn Repo.ancestors(c: Int) Set[Int]:
	var seen = Set[Int]()
	if c < 0: return seen
	var stack = [c]
	seen.add(c)
	while stack.length() > 0:
		x := stack.pop().get(-1)
		for p in self.commits[x].parents:
			if not seen.contains(p):
				seen.add(p.clone())
				stack.append(p)
	return seen

fn Repo.is_ancestor(a: Int, b: Int) Bool:
	return self.ancestors(b).contains(a)

fn var Repo.make_commit(tree: Map[String, String], parents: List[Int], msg: String) Int:
	var text = "tree {tree_hash(tree)}\n"
	for p in parents:
		text += "parent {self.commits[p].id}\n"
	text += "\n{msg}\n"
	id := hash_of(text)
	if self.ids.contains(id):
		return self.ids.get_or(id, 0)
	n := self.commits.length()
	self.commits.append(Commit(id.clone(), parents.clone(), msg.clone(), tree.clone()))
	self.ids[id] = n
	return n

fn var Repo.advance(c: Int) Unit:
	if self.detached:
		self.hcommit = c
	else:
		self.branches[self.hbranch.clone()] = c

fn var Repo.clear_merge() Unit:
	self.merging = false
	self.mbranch = ""
	self.mother = -1
	self.conflicts = Set[String]()

fn Repo.dirty() Bool:
	ht := self.tree_of(self.cur())
	if not tree_eq(self.index, ht): return true
	for e in self.index.entries():
		if w := self.work.get(e.key):
			if w != e.value: return true
		else:
			return true
	return false

fn Repo.untracked_in(tree: Map[String, String]) String?:
	for k in sorted_keys(tree):
		if not self.index.contains(k) and self.work.contains(k):
			return k.clone()
	return none

fn var Repo.switch_tree(tree: Map[String, String]) Unit:
	for k in self.index.keys():
		self.work.remove(k.clone())
	for e in tree.entries():
		self.work[e.key.clone()] = e.value.clone()
	self.index = tree.clone()

fn var Repo.cmd_write(name: String, lines: List[String], append: Bool) Unit:
	var c = ""
	if append:
		c = self.work.get_or(name, "")
	c += content_of(lines)
	self.work[name.clone()] = c

fn var Repo.cmd_add(args: List[String]) Unit!:
	if args.length() == 0: return fail("usage: add PATH...")
	for p in args:
		if p == ".":
			for e in self.work.entries():
				self.index[e.key.clone()] = e.value.clone()
				self.conflicts.remove(e.key.clone())
			for k in self.index.keys().clone():
				if not self.work.contains(k):
					self.index.remove(k.clone())
					self.conflicts.remove(k.clone())
		else if self.work.contains(p):
			self.index[p.clone()] = self.work.get_or(p, "")
			self.conflicts.remove(p.clone())
		else if self.index.contains(p):
			self.index.remove(p.clone())
			self.conflicts.remove(p.clone())
		else if self.conflicts.contains(p):
			self.conflicts.remove(p.clone())
		else:
			return fail("pathspec '{p}' did not match any files")
	return ok(unit)

fn var Repo.cmd_status() Unit:
	if self.detached:
		out("HEAD detached at {self.sid(self.hcommit)}")
	else:
		out("On branch {self.hbranch}")
	if self.merging:
		out("merging: {self.mbranch}")
	ht := self.tree_of(self.cur())
	var staged = List[String]()
	var names = Set[String]()
	for k in ht.keys(): names.add(k.clone())
	for k in self.index.keys(): names.add(k.clone())
	var nl = List[String]()
	for k in names: nl.append(k.clone())
	nl.sort()
	for k in nl:
		if self.conflicts.contains(k): continue
		inh := ht.contains(k)
		ini := self.index.contains(k)
		if ini and not inh:
			staged.append("new file: {k}")
		else if inh and not ini:
			staged.append("deleted: {k}")
		else if ht.get_or(k, "") != self.index.get_or(k, ""):
			staged.append("modified: {k}")
	var unstaged = List[String]()
	for k in sorted_keys(self.index):
		if self.conflicts.contains(k): continue
		if w := self.work.get(k):
			if w != self.index.get_or(k, ""):
				unstaged.append("modified: {k}")
		else:
			unstaged.append("deleted: {k}")
	var confl = List[String]()
	for k in self.conflicts: confl.append("unmerged: {k}")
	confl.sort()
	var untr = List[String]()
	for k in sorted_keys(self.work):
		if not self.index.contains(k) and not self.conflicts.contains(k):
			untr.append(k.clone())
	if staged.length() + unstaged.length() + confl.length() + untr.length() == 0:
		out("nothing to commit, working tree clean")
		return
	if staged.length() > 0:
		out("staged:")
		for s in staged: out("  {s}")
	if unstaged.length() > 0:
		out("unstaged:")
		for s in unstaged: out("  {s}")
	if confl.length() > 0:
		out("conflicts:")
		for s in confl: out("  {s}")
	if untr.length() > 0:
		out("untracked:")
		for s in untr: out("  {s}")

fn var Repo.cmd_commit(msg: String) Unit!:
	if msg == "": return fail("empty commit message")
	if self.conflicts.length() > 0:
		var cl = List[String]()
		for k in self.conflicts: cl.append(k.clone())
		cl.sort()
		return fail("unresolved conflicts: {cl.join(" ")}")
	cur := self.cur()
	label := self.label()
	if self.merging:
		id := self.make_commit(self.index.clone(), [cur, self.mother], msg)
		self.advance(id)
		self.clear_merge()
		out("[{label} {self.sid(id)}] {msg}")
		return ok(unit)
	if tree_eq(self.index, self.tree_of(cur)):
		return fail("nothing to commit")
	var parents = List[Int]()
	if cur >= 0: parents.append(cur)
	id := self.make_commit(self.index.clone(), parents, msg)
	self.advance(id)
	if cur < 0:
		out("[{label} (root-commit) {self.sid(id)}] {msg}")
	else:
		out("[{label} {self.sid(id)}] {msg}")
	return ok(unit)

fn Repo.cmd_log(args: List[String]) Unit!:
	var limit = -1
	if args.length() == 2 and args[0] == "-n" and is_digits(args[1]):
		if n := args[1].parse_int():
			limit = n
		else:
			return fail("usage: log [-n N]")
	else if args.length() != 0:
		return fail("usage: log [-n N]")
	cur := self.cur()
	if cur < 0:
		out("no commits yet")
		return ok(unit)
	var cs = List[Int]()
	for c in self.ancestors(cur): cs.append(c)
	cs.sort(fn a, b: b - a)
	var count = 0
	for c in cs:
		if limit >= 0 and count >= limit: break
		count += 1
		cm := self.commits[c]
		if cm.parents.length() == 2:
			out("{self.sid(c)} {cm.msg} (merge {self.sid(cm.parents[0])} {self.sid(cm.parents[1])})")
		else:
			out(self.line(c))
	return ok(unit)

fn Repo.cmd_diff(args: List[String]) Unit!:
	if args.length() > 2: return fail("usage: diff [REF [REF]]")
	var left = Map[String, String]()
	var right = Map[String, String]()
	if args.length() == 0:
		left = self.index.clone()
		right = self.work.clone()
	else if args.length() == 1:
		c := self.resolve(args[0])?
		left = self.tree_of(c)
		right = self.work.clone()
	else:
		c1 := self.resolve(args[0])?
		c2 := self.resolve(args[1])?
		left = self.tree_of(c1)
		right = self.tree_of(c2)
	var names = Set[String]()
	for k in left.keys(): names.add(k.clone())
	for k in right.keys(): names.add(k.clone())
	var nl = List[String]()
	for k in names: nl.append(k.clone())
	nl.sort()
	var any = false
	for k in nl:
		l := left.get(k)
		r := right.get(k)
		if l.is_some() and r.is_some() and l.get("") == r.get(""): continue
		any = true
		out("diff {k}")
		if l.is_none(): out("new file")
		if r.is_none(): out("deleted file")
		for d in line_diff(lines_of(l.get("")), lines_of(r.get(""))): out(d)
	if not any: out("(no differences)")
	return ok(unit)

fn var Repo.cmd_branch(args: List[String]) Unit!:
	if args.length() == 0:
		if self.detached:
			out("* (HEAD detached at {self.sid(self.hcommit)})")
		var names = List[String]()
		for k in self.branches.keys(): names.append(k.clone())
		names.sort()
		for n in names:
			if not self.detached and n == self.hbranch:
				out("* {n}")
			else:
				out("  {n}")
		return ok(unit)
	if args.length() == 2 and args[0] == "-d":
		name := args[1]
		if not self.branches.contains(name): return fail("branch '{name}' not found")
		if not self.detached and name == self.hbranch:
			return fail("cannot delete the current branch '{name}'")
		c := self.branches.get_or(name, -1)
		if c < 0 or not self.is_ancestor(c, self.cur()):
			return fail("branch '{name}' is not fully merged")
		self.branches.remove(name.clone())
		out("Deleted branch {name} (was {self.sid(c)}).")
		return ok(unit)
	if args.length() != 1: return fail("usage: branch [NAME | -d NAME]")
	self.create_branch(args[0])?
	return ok(unit)

fn var Repo.create_branch(name: String) Unit!:
	if not valid_name(name): return fail("invalid branch name '{name}'")
	if self.branches.contains(name): return fail("branch '{name}' already exists")
	c := self.cur()
	if c < 0: return fail("no commits yet")
	self.branches[name.clone()] = c
	return ok(unit)

fn var Repo.cmd_tag(args: List[String]) Unit!:
	if args.length() == 0:
		var names = List[String]()
		for k in self.tags.keys(): names.append(k.clone())
		names.sort()
		for n in names: out(n)
		return ok(unit)
	if args.length() > 2: return fail("usage: tag [NAME [REF]]")
	name := args[0]
	if not valid_name(name): return fail("invalid tag name '{name}'")
	if self.tags.contains(name): return fail("tag '{name}' already exists")
	if args.length() == 1 or args[1] == "HEAD":
		if self.cur() < 0: return fail("no commits yet")
	var c = 0
	if args.length() == 1:
		c = self.cur()
	else:
		c = self.resolve(args[1])?
	self.tags[name.clone()] = c
	return ok(unit)

fn Repo.cmd_show(args: List[String]) Unit!:
	if args.length() != 1: return fail("usage: show REF")
	c := self.resolve(args[0])?
	cm := self.commits[c]
	out("commit {cm.id}")
	out("tree {tree_hash(cm.tree)}")
	for p in cm.parents: out("parent {self.commits[p].id}")
	out("message: {cm.msg}")
	out("files:")
	for k in sorted_keys(cm.tree):
		out("  {k} {short(hash_of(cm.tree.get_or(k, "")))}")
	return ok(unit)

fn var Repo.cmd_checkout(args: List[String]) Unit!:
	if args.length() == 2 and args[0] == "-b":
		self.create_branch(args[1])?
		self.detached = false
		self.hbranch = args[1].clone()
		out("Switched to a new branch '{args[1]}'")
		return ok(unit)
	if args.length() != 1: return fail("usage: checkout REF | checkout -b NAME")
	if self.merging: return fail("merge in progress")
	t := args[0]
	if self.branches.contains(t):
		if not self.detached and self.hbranch == t:
			out("Already on '{t}'")
			return ok(unit)
		if self.dirty(): return fail("local changes would be overwritten")
		c := self.branches.get_or(t, -1)
		tree := self.tree_of(c)
		if u := self.untracked_in(tree):
			return fail("untracked file would be overwritten: {u}")
		self.switch_tree(tree)
		self.detached = false
		self.hbranch = t.clone()
		out("Switched to branch '{t}'")
		return ok(unit)
	c := self.resolve(t)?
	if self.dirty(): return fail("local changes would be overwritten")
	tree := self.tree_of(c)
	if u := self.untracked_in(tree):
		return fail("untracked file would be overwritten: {u}")
	self.switch_tree(tree)
	self.detached = true
	self.hcommit = c
	out("HEAD is now at {self.line(c)}")
	return ok(unit)

fn var Repo.hard_reset(c: Int) Unit:
	old := self.tree_of(self.cur())
	for k in self.index.keys(): self.work.remove(k.clone())
	for k in old.keys(): self.work.remove(k.clone())
	self.advance(c)
	tree := self.tree_of(c)
	for e in tree.entries():
		self.work[e.key.clone()] = e.value.clone()
	self.index = tree.clone()
	self.clear_merge()

fn var Repo.cmd_reset(args: List[String]) Unit!:
	if args.length() == 0 or args.length() > 2 or args[0] != "--hard":
		return fail("usage: reset --hard [REF]")
	var c = 0
	if args.length() == 1:
		c = self.cur()
		if c < 0: return fail("no commits yet")
	else:
		c = self.resolve(args[1])?
	self.hard_reset(c)
	out("HEAD is now at {self.line(c)}")
	return ok(unit)

fn var Repo.cmd_merge(args: List[String]) Unit!:
	if args.length() == 1 and args[0] == "--abort":
		if not self.merging: return fail("no merge in progress")
		self.hard_reset(self.cur())
		out("Merge aborted.")
		return ok(unit)
	if args.length() != 1: return fail("usage: merge BRANCH")
	br := args[0]
	if self.merging: return fail("merge in progress")
	cur := self.cur()
	if cur < 0: return fail("no commits yet")
	other := self.branches.get_or(br, -1)
	if other < 0: return fail("unknown branch '{br}'")
	if self.dirty(): return fail("local changes would be overwritten")
	if self.is_ancestor(other, cur):
		out("Already up to date.")
		return ok(unit)
	if self.is_ancestor(cur, other):
		tree := self.tree_of(other)
		if u := self.untracked_in(tree):
			return fail("untracked file would be overwritten: {u}")
		self.switch_tree(tree)
		self.advance(other)
		out("Fast-forward")
		return ok(unit)
	ca := self.ancestors(cur)
	oa := self.ancestors(other)
	var bc = -1
	for c in ca:
		if oa.contains(c) and c > bc: bc = c
	bt := self.tree_of(bc)
	ot := self.tree_of(cur)
	tt := self.tree_of(other)
	var names = Set[String]()
	for k in bt.keys(): names.add(k.clone())
	for k in ot.keys(): names.add(k.clone())
	for k in tt.keys(): names.add(k.clone())
	var nl = List[String]()
	for k in names: nl.append(k.clone())
	nl.sort()
	var result = Map[String, String]()
	var over = Map[String, String]()
	var kinds = Map[String, String]()
	for k in nl:
		o := ot.get(k)
		t := tt.get(k)
		b := bt.get(k)
		same_ot := o.is_none() == t.is_none() and o.get("") == t.get("")
		o_b := o.is_none() == b.is_none() and o.get("") == b.get("")
		t_b := t.is_none() == b.is_none() and t.get("") == b.get("")
		if same_ot or t_b:
			if o.is_some(): result[k.clone()] = o.get("")
		else if o_b:
			if t.is_some(): result[k.clone()] = t.get("")
		else if o.is_none() or t.is_none():
			if o.is_some():
				result[k.clone()] = o.get("")
				over[k.clone()] = o.get("")
			else:
				over[k.clone()] = t.get("")
			kinds[k.clone()] = "modify/delete"
		else:
			m := merge3(lines_of(b.get("")), lines_of(o.get("")), lines_of(t.get("")), br)
			text := content_of(m.lines)
			if m.conflict:
				result[k.clone()] = o.get("")
				over[k.clone()] = text
				kinds[k.clone()] = if b.is_some(): "content" else: "add/add"
			else:
				result[k.clone()] = text
	var chk = Set[String]()
	for k in result.keys(): chk.add(k.clone())
	for k in over.keys(): chk.add(k.clone())
	var cl = List[String]()
	for k in chk: cl.append(k.clone())
	cl.sort()
	for k in cl:
		if not self.index.contains(k) and self.work.contains(k):
			return fail("untracked file would be overwritten: {k}")
	for k in self.index.keys():
		if not result.contains(k): self.work.remove(k.clone())
	for e in result.entries(): self.work[e.key.clone()] = e.value.clone()
	for e in over.entries(): self.work[e.key.clone()] = e.value.clone()
	self.index = result.clone()
	if kinds.length() == 0:
		id := self.make_commit(result, [cur, other], "Merge branch '{br}'")
		label := self.label()
		self.advance(id)
		out("Merge made by the 'three-way' strategy.")
		out("[{label} {self.sid(id)}] Merge branch '{br}'")
		return ok(unit)
	self.merging = true
	self.mbranch = br.clone()
	self.mother = other
	var ks = List[String]()
	for k in kinds.keys(): ks.append(k.clone())
	ks.sort()
	for k in ks:
		self.conflicts.add(k.clone())
		kind := kinds.get_or(k, "")
		if kind == "modify/delete":
			out("CONFLICT (modify/delete): {k}")
		else:
			out("CONFLICT ({kind}): Merge conflict in {k}")
	out("Automatic merge failed; fix conflicts and then commit the result.")
	return ok(unit)

fn var Repo.dispatch(cmd: String, args: List[String], rest: String) Unit!:
	if cmd == "rm":
		if args.length() == 0: return fail("usage: rm FILE...")
		for a in args:
			if not self.work.contains(a): return fail("no such file: {a}")
			self.work.remove(a)
	else if cmd == "mv":
		if args.length() != 2: return fail("usage: mv OLD NEW")
		if not self.work.contains(args[0]): return fail("no such file: {args[0]}")
		if args[0] != args[1]:
			v := self.work.get_or(args[0], "")
			self.work.remove(args[0].clone())
			self.work[args[1].clone()] = v
	else if cmd == "cat":
		if args.length() != 1: return fail("usage: cat FILE")
		if not self.work.contains(args[0]): return fail("no such file: {args[0]}")
		for l in lines_of(self.work.get_or(args[0], "")): out(l)
	else if cmd == "ls":
		if self.work.length() == 0:
			out("(empty)")
		else:
			for k in sorted_keys(self.work): out(k)
	else if cmd == "add":
		self.cmd_add(args)?
	else if cmd == "status":
		self.cmd_status()
	else if cmd == "commit":
		self.cmd_commit(rest)?
	else if cmd == "log":
		self.cmd_log(args)?
	else if cmd == "diff":
		self.cmd_diff(args)?
	else if cmd == "branch":
		self.cmd_branch(args)?
	else if cmd == "tag":
		self.cmd_tag(args)?
	else if cmd == "show":
		self.cmd_show(args)?
	else if cmd == "checkout":
		self.cmd_checkout(args)?
	else if cmd == "merge":
		self.cmd_merge(args)?
	else if cmd == "reset":
		self.cmd_reset(args)?
	else:
		return fail("unknown command '{cmd}'")
	return ok(unit)

// ms: allow_effect std.console.read
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().ok_or(Error("invalid input"))?
	var all = List[String]()
	for part in text.split("\n"): all.append(part.clone())
	if all.length() > 0 and all[all.length() - 1] == "":
		all.pop()
	var repo = Repo()
	repo.branches["main"] = -1
	var i = 0
	while i < all.length():
		raw := all[i]
		i += 1
		t := raw.trim()
		if t == "" or t.starts_with("#"): continue
		out("> {raw.trim_end()}")
		toks := t.replace("\t", " ").split(" ").filter(fn s: s != "")
		cmd := toks[0].clone()
		var args = List[String]()
		for j in 1..toks.length(): args.append(toks[j].clone())
		if cmd == "write" or cmd == "append":
			if args.length() != 1:
				out("error: usage: {cmd} FILE")
				continue
			var block = List[String]()
			while i < all.length() and all[i] != ".":
				block.append(all[i].clone())
				i += 1
			if i < all.length(): i += 1
			repo.cmd_write(args[0], block, cmd == "append")
			continue
		var rest = ""
		if cmd == "commit":
			if r := t.slice(6, t.length()):
				rest = r.trim()
		res := repo.dispatch(cmd, args, rest)
		if _v := res:
			unit
		else:
			out("error: {res.err().message}")
