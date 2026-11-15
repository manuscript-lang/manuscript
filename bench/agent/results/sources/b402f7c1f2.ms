import stdin from "@std/io/io.ms"
import lines, collect from "@std/io/streams.ms"
import shift_right_unsigned, bit_xor, bit_and, wrapping_multiply from "@std/math/math.ms"

type Commit:
	id: String
	parents: List[String]
	message: String
	tree: Map[String, String]
	num: Int

type Repo:
	work: Map[String, String] = Map[String, String]()
	index: Map[String, String] = Map[String, String]()
	commits: List[Commit] = List[Commit]()
	branches: Map[String, String] = Map[String, String]()
	tags: Map[String, String] = Map[String, String]()
	head_branch: String = "main"
	head_commit: String = ""
	merging: Bool = false
	merge_other: String = ""
	merge_branch: String = ""
	conflicts: Set[String] = Set[String]()
	out: List[String] = List[String]()

fn fnv(s: String) String:
	var h = -3750763034362895579
	bytes := s.as_bytes()
	for i in 0..bytes.length():
		h = wrapping_multiply(bit_xor(h, bytes.get(i).to_int()), 1099511628211)
	var r = ""
	for i in 0..16:
		nib := bit_and(shift_right_unsigned(h, 60 - 4 * i), 15)
		r = r + nib.to_string_radix(16)
	return r

fn short(id: String) String:
	return id.slice(0, 7).get("")

fn sorted_list(xs: List[String]) List[String]:
	var r = List[String]()
	for x in xs: r.append(x.clone())
	r.sort()
	return r

fn sorted_keys(m: Map[String, String]) List[String]:
	return sorted_list(m.keys())

fn tree_hash(t: Map[String, String]) String:
	var text = ""
	for k in sorted_keys(t):
		text = text + k + " " + fnv(t.get_or(k, "")) + "\n"
	return fnv(text)

fn tree_eq(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for e in a.entries():
		if not b.contains(e.key): return false
		if b.get_or(e.key, "") != e.value: return false
	return true

fn lines_of(content: String) List[String]:
	var r = List[String]()
	if content == "": return r
	parts := content.split("\n")
	for i in 0..parts.length() - 1:
		r.append(parts.get(i, ""))
	return r

fn to_content(ls: List[String]) String:
	var r = ""
	for l in ls:
		r = r + l + "\n"
	return r

fn sub(xs: List[String], a: Int, b: Int) List[String]:
	var r = List[String]()
	var i = a
	while i < b:
		r.append(xs.get(i, ""))
		i += 1
	return r

// flattened pairs i0,j0,i1,j1,...
fn matching(a: List[String], b: List[String]) List[Int]:
	n := a.length()
	m := b.length()
	w := m + 1
	var l = List[Int]()
	for _x in 0..(n + 1) * w:
		l.append(0)
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a.get(i, "") == b.get(j, ""):
				l[i * w + j] = 1 + l.get((i + 1) * w + j + 1, 0)
			else:
				x := l.get((i + 1) * w + j, 0)
				y := l.get(i * w + j + 1, 0)
				l[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	var r = List[Int]()
	var p = 0
	var q = 0
	while p < n and q < m:
		if a.get(p, "") == b.get(q, ""):
			r.append(p)
			r.append(q)
			p += 1
			q += 1
		else if l.get((p + 1) * w + q, 0) >= l.get(p * w + q + 1, 0):
			p += 1
		else:
			q += 1
	return r

fn line_diff(a: List[String], b: List[String]) List[String]:
	pairs := matching(a, b)
	var out = List[String]()
	var p = 0
	var q = 0
	var k = 0
	while k < pairs.length():
		pi := pairs.get(k, 0)
		pj := pairs.get(k + 1, 0)
		while p < pi:
			out.append("- " + a.get(p, ""))
			p += 1
		while q < pj:
			out.append("+ " + b.get(q, ""))
			q += 1
		out.append("  " + a.get(pi, ""))
		p = pi + 1
		q = pj + 1
		k += 2
	while p < a.length():
		out.append("- " + a.get(p, ""))
		p += 1
	while q < b.length():
		out.append("+ " + b.get(q, ""))
		q += 1
	return out

type Merged:
	text: List[String]
	clean: Bool

fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) Merged:
	nb := base.length()
	var bo = List[Int]()
	var bt = List[Int]()
	for _x in 0..nb:
		bo.append(-1)
		bt.append(-1)
	po := matching(base, ours)
	var k = 0
	while k < po.length():
		bo[po.get(k, 0)] = po.get(k + 1, 0)
		k += 2
	pt := matching(base, theirs)
	k = 0
	while k < pt.length():
		bt[pt.get(k, 0)] = pt.get(k + 1, 0)
		k += 2
	var out = List[String]()
	var clean = true
	var pb = -1
	var pos = -1
	var pts = -1
	for s in 0..nb + 1:
		var so = ours.length()
		var st = theirs.length()
		if s < nb:
			if bo.get(s, -1) < 0 or bt.get(s, -1) < 0: continue
			so = bo.get(s, 0)
			st = bt.get(s, 0)
		bc := sub(base, pb + 1, s)
		oc := sub(ours, pos + 1, so)
		tc := sub(theirs, pts + 1, st)
		if oc == bc:
			for l in tc: out.append(l.clone())
		else if tc == bc:
			for l in oc: out.append(l.clone())
		else if oc == tc:
			for l in oc: out.append(l.clone())
		else:
			clean = false
			out.append("<<<<<<< HEAD")
			for l in oc: out.append(l.clone())
			out.append("=======")
			for l in tc: out.append(l.clone())
			out.append(">>>>>>> " + branch)
		if s < nb:
			out.append(base.get(s, ""))
		pb = s
		pos = so
		pts = st
	return Merged(out, clean)

fn valid_name(n: String) Bool:
	if n == "": return false
	for i in 0..n.length():
		c := n.slice(i, i + 1).get("")
		ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "." or c == "_" or c == "/"
		if ok: continue
		if c == "-" and i > 0: continue
		return false
	return true

fn is_digits(s: String) Bool:
	if s == "": return false
	for i in 0..s.length():
		c := s.slice(i, i + 1).get("")
		if not (c >= "0" and c <= "9"): return false
	return true

fn is_hex(s: String) Bool:
	if s == "": return false
	for i in 0..s.length():
		c := s.slice(i, i + 1).get("")
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")): return false
	return true

fn fail[T](msg: String) T!:
	return error(Error(msg))

fn Repo.head() String:
	if self.head_branch != "": return self.branches.get_or(self.head_branch, "").clone()
	return self.head_commit.clone()

fn Repo.find(id: String) Int:
	for i in 0..self.commits.length():
		if self.commits[i].id == id: return i
	return -1

fn Repo.tree_of(id: String) Map[String, String]:
	if id == "": return Map[String, String]()
	i := self.find(id)
	return self.commits[i].tree.clone()

fn Repo.head_tree() Map[String, String]:
	return self.tree_of(self.head())

fn Repo.ancestors(id: String) Set[String]:
	var seen = Set[String]()
	var stack = [id.clone()]
	while stack.length() > 0:
		cur := stack.pop().get("")
		if seen.contains(cur): continue
		seen.add(cur.clone())
		i := self.find(cur)
		if i < 0: continue
		for p in self.commits[i].parents:
			stack.append(p.clone())
	return seen

fn Repo.msg_of(id: String) String:
	return self.commits[self.find(id)].message.clone()

fn var Repo.emit(s: String) Unit:
	self.out.append(s)

fn Repo.resolve(rv: String) String!:
	var base = rv.clone()
	var steps = 0
	idx := rv.index_of("~")
	if idx_v := idx:
		base = rv.slice(0, idx_v).get("")
		rest := rv.slice(idx_v + 1, rv.length()).get("")
		if not is_digits(rest): return fail("unknown revision '{rv}'")
		if n := rest.parse_int():
			steps = n
		else:
			return fail("unknown revision '{rv}'")
	var id = ""
	if base == "HEAD":
		id = self.head()
		if id == "": return fail("unknown revision '{rv}'")
	else if self.branches.get_or(base, "") != "":
		id = self.branches.get_or(base, "")
	else if self.tags.contains(base):
		id = self.tags.get_or(base, "")
	else if base.length() >= 4 and is_hex(base):
		var found = List[String]()
		for c in self.commits:
			if c.id.starts_with(base): found.append(c.id.clone())
		if found.length() > 1: return fail("ambiguous revision '{rv}'")
		if found.length() == 0: return fail("unknown revision '{rv}'")
		id = found.get(0, "")
	else:
		return fail("unknown revision '{rv}'")
	var s = 0
	while s < steps:
		i := self.find(id)
		if self.commits[i].parents.length() == 0: return fail("unknown revision '{rv}'")
		id = self.commits[i].parents.get(0, "")
		s += 1
	return ok(id)

fn var Repo.make_commit(tree: Map[String, String], parents: List[String], message: String) String:
	var text = "tree " + tree_hash(tree) + "\n"
	for p in parents:
		text = text + "parent " + p + "\n"
	text = text + "\n" + message + "\n"
	id := fnv(text)
	if self.find(id) >= 0: return id
	self.commits.append(Commit(id.clone(), parents.clone(), message.clone(), tree.clone(), self.commits.length() + 1))
	return id

fn var Repo.move_head(id: String) Unit:
	if self.head_branch != "":
		self.branches[self.head_branch.clone()] = id.clone()
	else:
		self.head_commit = id.clone()

fn Repo.dirty() Bool:
	if not tree_eq(self.index, self.head_tree()): return true
	for e in self.index.entries():
		if not self.work.contains(e.key): return true
		if self.work.get_or(e.key, "") != e.value: return true
	return false

fn Repo.untracked_check(tree: Map[String, String]) Unit!:
	for k in sorted_keys(tree):
		if not self.index.contains(k) and self.work.contains(k):
			return fail("untracked file would be overwritten: {k}")

fn var Repo.switch_tree(tree: Map[String, String]) Unit:
	for k in self.index.keys():
		self.work.remove(k.clone())
	for e in tree.entries():
		self.work[e.key.clone()] = e.value.clone()
	self.index = tree.clone()

fn var Repo.reset_hard(id: String) Unit:
	for k in self.index.keys():
		self.work.remove(k.clone())
	for k in self.head_tree().keys():
		self.work.remove(k.clone())
	tree := self.tree_of(id)
	for e in tree.entries():
		self.work[e.key.clone()] = e.value.clone()
	self.index = tree.clone()
	self.move_head(id)
	self.merging = false
	self.conflicts = Set[String]()

fn Repo.branch_label() String:
	if self.head_branch != "": return self.head_branch.clone()
	return "detached"

fn var Repo.cmd_branch_create(name: String) Unit!:
	if not valid_name(name): return fail("invalid branch name '{name}'")
	if self.branches.contains(name): return fail("branch '{name}' already exists")
	h := self.head()
	if h == "": return fail("no commits yet")
	self.branches[name.clone()] = h
	return ok(unit)

fn var Repo.cmd_branch(args: List[String]) Unit!:
	if args.length() == 0:
		names := sorted_list(self.branches.keys())
		if self.head_branch == "":
			self.emit("* (HEAD detached at {short(self.head_commit)})")
		for n in names:
			if n == self.head_branch: self.emit("* {n}")
			else: self.emit("  {n}")
		return ok(unit)
	if args.length() == 1:
		return self.cmd_branch_create(args.get(0, ""))
	if args.length() == 2 and args.get(0, "") == "-d":
		name := args.get(1, "")
		if not self.branches.contains(name): return fail("branch '{name}' not found")
		if name == self.head_branch: return fail("cannot delete the current branch '{name}'")
		bid := self.branches.get_or(name, "")
		h := self.head()
		if bid != h and not self.ancestors(h).contains(bid): return fail("branch '{name}' is not fully merged")
		self.branches.remove(name.clone())
		self.emit("Deleted branch {name} (was {short(bid)}).")
		return ok(unit)
	return fail("usage: branch [NAME | -d NAME]")

fn var Repo.cmd_tag(args: List[String]) Unit!:
	if args.length() == 0:
		names := sorted_list(self.tags.keys())
		for n in names: self.emit(n)
		return ok(unit)
	if args.length() > 2: return fail("usage: tag [NAME [REF]]")
	name := args.get(0, "")
	if not valid_name(name): return fail("invalid tag name '{name}'")
	if self.tags.contains(name): return fail("tag '{name}' already exists")
	var rv = "HEAD"
	if args.length() == 2: rv = args.get(1, "")
	if rv == "HEAD" and self.head() == "": return fail("no commits yet")
	id := self.resolve(rv)?
	self.tags[name.clone()] = id
	return ok(unit)

fn var Repo.cmd_checkout(args: List[String]) Unit!:
	if args.length() == 2 and args.get(0, "") == "-b":
		name := args.get(1, "")
		self.cmd_branch_create(name)?
		self.head_branch = name.clone()
		self.head_commit = ""
		self.emit("Switched to a new branch '{name}'")
		return ok(unit)
	if args.length() != 1: return fail("usage: checkout REF | checkout -b NAME")
	if self.merging: return fail("merge in progress")
	target := args.get(0, "")
	if self.branches.contains(target):
		if target == self.head_branch:
			self.emit("Already on '{target}'")
			return ok(unit)
		bid := self.branches.get_or(target, "")
		if self.dirty(): return fail("local changes would be overwritten")
		tree := self.tree_of(bid)
		self.untracked_check(tree)?
		self.switch_tree(tree)
		self.head_branch = target.clone()
		self.head_commit = ""
		self.emit("Switched to branch '{target}'")
		return ok(unit)
	id := self.resolve(target)?
	if self.dirty(): return fail("local changes would be overwritten")
	tree := self.tree_of(id)
	self.untracked_check(tree)?
	self.switch_tree(tree)
	self.head_branch = ""
	self.head_commit = id.clone()
	self.emit("HEAD is now at {short(id)} {self.msg_of(id)}")
	return ok(unit)

fn var Repo.cmd_commit(rest: String) Unit!:
	if rest == "": return fail("empty commit message")
	if self.conflicts.length() > 0:
		names := sorted_list(self.conflicts.values())
		return fail("unresolved conflicts: {names.join(" ")}")
	h := self.head()
	if self.merging:
		id := self.make_commit(self.index.clone(), [h.clone(), self.merge_other.clone()], rest)
		self.move_head(id)
		self.merging = false
		self.emit("[{self.branch_label()} {short(id)}] {rest}")
		return ok(unit)
	if tree_eq(self.index, self.head_tree()): return fail("nothing to commit")
	var parents = List[String]()
	if h != "": parents.append(h.clone())
	id := self.make_commit(self.index.clone(), parents, rest)
	self.move_head(id)
	if h == "": self.emit("[{self.branch_label()} (root-commit) {short(id)}] {rest}")
	else: self.emit("[{self.branch_label()} {short(id)}] {rest}")
	return ok(unit)

fn var Repo.cmd_log(args: List[String]) Unit!:
	var limit = -1
	if args.length() != 0:
		if args.length() != 2 or args.get(0, "") != "-n" or not is_digits(args.get(1, "")): return fail("usage: log [-n N]")
		if n := args.get(1, "").parse_int():
			limit = n
		else:
			limit = 9223372036854775807
	h := self.head()
	if h == "": return fail("no commits yet")
	reach := self.ancestors(h)
	var count = 0
	var i = self.commits.length() - 1
	while i >= 0:
		if limit >= 0 and count >= limit: break
		c := self.commits[i]
		if reach.contains(c.id):
			var line = "{short(c.id)} {c.message}"
			if c.parents.length() == 2:
				line = line + " (merge {short(c.parents.get(0, ""))} {short(c.parents.get(1, ""))})"
			self.out.append(line)
			count += 1
		i -= 1
	return ok(unit)

fn var Repo.cmd_show(args: List[String]) Unit!:
	if args.length() != 1: return fail("usage: show REF")
	id := self.resolve(args.get(0, ""))?
	c := self.commits[self.find(id)].clone()
	self.emit("commit {c.id}")
	self.emit("tree {tree_hash(c.tree)}")
	for p in c.parents: self.emit("parent {p}")
	self.emit("message: {c.message}")
	self.emit("files:")
	for k in sorted_keys(c.tree):
		self.emit("  {k} {short(fnv(c.tree.get_or(k, "")))}")
	return ok(unit)

fn diff_trees(a: Map[String, String], b: Map[String, String]) List[String]:
	var out = List[String]()
	var names = Set[String]()
	for k in a.keys(): names.add(k.clone())
	for k in b.keys(): names.add(k.clone())
	ks := sorted_list(names.values())
	var any = false
	for k in ks:
		ina := a.contains(k)
		inb := b.contains(k)
		if ina and inb and a.get_or(k, "") == b.get_or(k, ""): continue
		any = true
		out.append("diff {k}")
		if not ina: out.append("new file")
		else if not inb: out.append("deleted file")
		for l in line_diff(lines_of(a.get_or(k, "")), lines_of(b.get_or(k, ""))):
			out.append(l)
	if not any: out.append("(no differences)")
	return out

fn var Repo.cmd_diff(args: List[String]) Unit!:
	if args.length() > 2: return fail("usage: diff [REF [REF]]")
	if args.length() == 0:
		self.out.extend(diff_trees(self.index.clone(), self.work.clone()))
	else if args.length() == 1:
		id := self.resolve(args.get(0, ""))?
		self.out.extend(diff_trees(self.tree_of(id), self.work.clone()))
	else:
		a := self.resolve(args.get(0, ""))?
		b := self.resolve(args.get(1, ""))?
		self.out.extend(diff_trees(self.tree_of(a), self.tree_of(b)))
	return ok(unit)

fn var Repo.cmd_status() Unit:
	if self.head_branch != "": self.emit("On branch {self.head_branch}")
	else: self.emit("HEAD detached at {short(self.head_commit)}")
	if self.merging: self.emit("merging: {self.merge_branch}")
	ht := self.head_tree()
	var names = Set[String]()
	for k in ht.keys(): names.add(k.clone())
	for k in self.index.keys(): names.add(k.clone())
	ks := sorted_list(names.values())
	var staged = List[String]()
	for k in ks:
		if self.conflicts.contains(k): continue
		inh := ht.contains(k)
		ini := self.index.contains(k)
		if ini and not inh: staged.append("new file: {k}")
		else if inh and not ini: staged.append("deleted: {k}")
		else if ht.get_or(k, "") != self.index.get_or(k, ""): staged.append("modified: {k}")
	var unstaged = List[String]()
	for k in sorted_keys(self.index):
		if self.conflicts.contains(k): continue
		if not self.work.contains(k): unstaged.append("deleted: {k}")
		else if self.work.get_or(k, "") != self.index.get_or(k, ""): unstaged.append("modified: {k}")
	var conf = List[String]()
	cl := sorted_list(self.conflicts.values())
	for k in cl: conf.append("unmerged: {k}")
	var untr = List[String]()
	for k in sorted_keys(self.work):
		if not self.index.contains(k) and not self.conflicts.contains(k): untr.append(k.clone())
	if staged.length() + unstaged.length() + conf.length() + untr.length() == 0:
		self.emit("nothing to commit, working tree clean")
		return
	if staged.length() > 0:
		self.emit("staged:")
		for s in staged: self.emit("  {s}")
	if unstaged.length() > 0:
		self.emit("unstaged:")
		for s in unstaged: self.emit("  {s}")
	if conf.length() > 0:
		self.emit("conflicts:")
		for s in conf: self.emit("  {s}")
	if untr.length() > 0:
		self.emit("untracked:")
		for s in untr: self.emit("  {s}")

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

fn var Repo.cmd_merge(args: List[String]) Unit!:
	if args.length() == 1 and args.get(0, "") == "--abort":
		if not self.merging: return fail("no merge in progress")
		self.reset_hard(self.head())
		self.emit("Merge aborted.")
		return ok(unit)
	if args.length() != 1: return fail("usage: merge BRANCH")
	if self.merging: return fail("merge in progress")
	cur := self.head()
	if cur == "": return fail("no commits yet")
	branch := args.get(0, "")
	other := self.branches.get_or(branch, "")
	if other == "": return fail("unknown branch '{branch}'")
	if self.dirty(): return fail("local changes would be overwritten")
	cur_anc := self.ancestors(cur)
	if cur_anc.contains(other):
		self.emit("Already up to date.")
		return ok(unit)
	other_anc := self.ancestors(other)
	if other_anc.contains(cur):
		tree := self.tree_of(other)
		self.untracked_check(tree)?
		self.switch_tree(tree)
		self.move_head(other)
		self.emit("Fast-forward")
		return ok(unit)
	var base_id = ""
	var best = 0
	for c in self.commits:
		if cur_anc.contains(c.id) and other_anc.contains(c.id) and c.num > best:
			best = c.num
			base_id = c.id.clone()
	bt := self.tree_of(base_id)
	ot := self.tree_of(cur)
	tt := self.tree_of(other)
	var names = Set[String]()
	for k in bt.keys(): names.add(k.clone())
	for k in ot.keys(): names.add(k.clone())
	for k in tt.keys(): names.add(k.clone())
	ks := sorted_list(names.values())
	var result = Map[String, String]()
	var overrides = Map[String, String]()
	var kinds = Map[String, String]()
	for k in ks:
		ino := ot.contains(k)
		int := tt.contains(k)
		inb := bt.contains(k)
		ov := ot.get_or(k, "")
		tv := tt.get_or(k, "")
		bv := bt.get_or(k, "")
		o_same_t := (not ino and not int) or (ino and int and ov == tv)
		o_eq_b := (ino == inb) and (not ino or ov == bv)
		t_eq_b := (int == inb) and (not int or tv == bv)
		if o_same_t or t_eq_b:
			if ino: result[k.clone()] = ov
		else if o_eq_b:
			if int: result[k.clone()] = tv
		else if ino != int:
			kinds[k.clone()] = "modify/delete"
			if ino:
				result[k.clone()] = ov.clone()
				overrides[k.clone()] = ov.clone()
			else:
				overrides[k.clone()] = tv
		else:
			m := merge3(lines_of(bv), lines_of(ov), lines_of(tv), branch)
			if m.clean:
				result[k.clone()] = to_content(m.text)
			else:
				result[k.clone()] = ov
				overrides[k.clone()] = to_content(m.text)
				kinds[k.clone()] = if inb: "content" else: "add/add"
	var check = Set[String]()
	for k in result.keys(): check.add(k.clone())
	for k in overrides.keys(): check.add(k.clone())
	cks := sorted_list(check.values())
	for k in cks:
		if not self.index.contains(k) and self.work.contains(k):
			return fail("untracked file would be overwritten: {k}")
	for k in self.index.keys():
		if not result.contains(k): self.work.remove(k.clone())
	for e in result.entries():
		self.work[e.key.clone()] = e.value.clone()
	for e in overrides.entries():
		self.work[e.key.clone()] = e.value.clone()
	self.index = result.clone()
	if kinds.length() == 0:
		id := self.make_commit(result, [cur.clone(), other.clone()], "Merge branch '{branch}'")
		self.move_head(id)
		self.emit("Merge made by the 'three-way' strategy.")
		self.emit("[{self.branch_label()} {short(id)}] Merge branch '{branch}'")
		return ok(unit)
	self.merging = true
	self.merge_other = other.clone()
	self.merge_branch = branch.clone()
	self.conflicts = Set[String]()
	for k in sorted_keys(kinds):
		self.conflicts.add(k.clone())
		kind := kinds.get_or(k, "")
		if kind == "modify/delete": self.emit("CONFLICT (modify/delete): {k}")
		else: self.emit("CONFLICT ({kind}): Merge conflict in {k}")
	self.emit("Automatic merge failed; fix conflicts and then commit the result.")
	return ok(unit)

fn var Repo.run(cmd: String, args: List[String], rest: String, block: List[String]) Unit!:
	if cmd == "write" or cmd == "append":
		var content = to_content(block)
		if cmd == "append": content = self.work.get_or(args.get(0, ""), "") + content
		self.work[args.get(0, "").clone()] = content
	else if cmd == "rm":
		if args.length() == 0: return fail("usage: rm FILE...")
		for a in args:
			if not self.work.contains(a): return fail("no such file: {a}")
			self.work.remove(a.clone())
	else if cmd == "mv":
		if args.length() != 2: return fail("usage: mv OLD NEW")
		o := args.get(0, "")
		n := args.get(1, "")
		if not self.work.contains(o): return fail("no such file: {o}")
		content := self.work.get_or(o, "")
		if o != n:
			self.work.remove(o.clone())
			self.work[n.clone()] = content
	else if cmd == "cat":
		if args.length() != 1: return fail("usage: cat FILE")
		f := args.get(0, "")
		if not self.work.contains(f): return fail("no such file: {f}")
		for l in lines_of(self.work.get_or(f, "")): self.emit(l)
	else if cmd == "ls":
		if self.work.length() == 0: self.emit("(empty)")
		for k in sorted_keys(self.work): self.emit(k)
	else if cmd == "add": self.cmd_add(args)?
	else if cmd == "status": self.cmd_status()
	else if cmd == "commit": self.cmd_commit(rest)?
	else if cmd == "log": self.cmd_log(args)?
	else if cmd == "diff": self.cmd_diff(args)?
	else if cmd == "branch": self.cmd_branch(args)?
	else if cmd == "tag": self.cmd_tag(args)?
	else if cmd == "show": self.cmd_show(args)?
	else if cmd == "checkout": self.cmd_checkout(args)?
	else if cmd == "merge": self.cmd_merge(args)?
	else if cmd == "reset":
		if args.length() == 0 or args.length() > 2 or args.get(0, "") != "--hard": return fail("usage: reset --hard [REF]")
		var id = ""
		if args.length() == 2:
			id = self.resolve(args.get(1, ""))?
		else:
			id = self.head()
			if id == "": return fail("no commits yet")
		self.reset_hard(id)
		self.emit("HEAD is now at {short(id)} {self.msg_of(id)}")
	else:
		return fail("unknown command '{cmd}'")
	return ok(unit)

fn tokens(line: String) List[String]:
	var r = List[String]()
	for t in line.replace("\t", " ").split(" "):
		if t != "": r.append(t.clone())
	return r

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	all := collect(lines(stdin()))?
	var repo = Repo()
	repo.branches["main"] = ""
	var i = 0
	while i < all.length():
		raw := all.get(i, "").trim_end()
		i += 1
		t := raw.trim()
		if t == "" or t.starts_with("#"): continue
		repo.emit("> {raw}")
		toks := tokens(t)
		cmd := toks.get(0, "")
		var args = List[String]()
		for j in 1..toks.length(): args.append(toks.get(j, ""))
		rest := t.slice(cmd.length(), t.length()).get("").trim()
		var block = List[String]()
		if (cmd == "write" or cmd == "append") and args.length() == 1:
			while i < all.length():
				l := all.get(i, "")
				i += 1
				if l == ".": break
				block.append(l.clone())
		if cmd == "write" or cmd == "append":
			if args.length() != 1:
				repo.emit("error: usage: {cmd} FILE")
				continue
		res := repo.run(cmd, args, rest, block)
		if _r := res:
			continue
		else:
			repo.emit("error: {res.err().message}")
	print(repo.out.join("\n"))
