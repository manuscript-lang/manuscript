import wrapping_multiply, bit_xor, bit_and, shift_right_unsigned from "@std/math/math.ms"
import stdin, stdout from "@std/io/io.ms"
import lines, collect from "@std/io/streams.ms"

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
	head_branch: String = "main"
	head_detached: Int = -1
	work: Map[String, String] = Map[String, String]()
	index: Map[String, String] = Map[String, String]()
	conflicts: Map[String, String] = Map[String, String]()
	merging: Bool = false
	merge_other: Int = -1
	merge_branch: String = ""
	out: List[String] = []

type MergeOut:
	lines: List[String]
	conflict: Bool

type Chunk:
	name: String
	kind: String

fn sl(s: String, a: Int, b: Int) String:
	r := s.slice(a, b)
	if x := r: return x
	return ""

fn fnv(s: String) Int:
	var h = -3750763034362895579
	for b in s.as_bytes().values():
		h = bit_xor(h, b.to_int())
		h = wrapping_multiply(h, 1099511628211)
	return h

fn hex16(h: Int) String:
	digits := "0123456789abcdef"
	var s = ""
	for i in 0..16:
		n := bit_and(shift_right_unsigned(h, 60 - 4 * i), 15)
		s = s + sl(digits, n, n + 1)
	return s

fn hash_hex(s: String) String: hex16(fnv(s))

fn tree_hash(t: Map[String, String]) String:
	var text = ""
	for name in t.keys().sorted():
		text = text + name + " " + hash_hex(t.get_or(name, "")) + "\n"
	return hash_hex(text)

fn tree_eq(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for name in a.keys():
		if x := a.get(name):
			if y := b.get(name):
				if x != y: return false
			else: return false
	return true

fn opt_same(a: String?, b: String?) Bool:
	if x := a:
		if y := b:
			return x == y
		return false
	return b.is_none()

fn lines_of(content: String) List[String]:
	if content == "": return List[String]()
	var parts = content.split("\n").clone()
	parts.remove(-1)
	return parts

fn content_of(ls: List[String]) String:
	var s = ""
	for l in ls:
		s = s + l + "\n"
	return s

fn sub(xs: List[String], a: Int, b: Int) List[String]:
	var r = List[String]()
	var i = a
	while i < b:
		r.append(xs[i].clone())
		i += 1
	return r

// for each index of a, matching index of b or -1
fn matching(a: List[String], b: List[String]) List[Int]:
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
	var p = 0
	var q = 0
	while p < n and q < m:
		if a[p] == b[q]:
			res[p] = q
			p += 1
			q += 1
		else if l[(p + 1) * w + q] >= l[p * w + q + 1]:
			p += 1
		else:
			q += 1
	return res

fn diff_lines(a: List[String], b: List[String]) List[String]:
	mt := matching(a, b)
	var out = List[String]()
	var pi = 0
	var pj = 0
	for i in 0..a.length():
		j := mt[i]
		if j < 0: continue
		while pi < i:
			out.append("- " + a[pi])
			pi += 1
		while pj < j:
			out.append("+ " + b[pj])
			pj += 1
		out.append("  " + a[i])
		pi = i + 1
		pj = j + 1
	while pi < a.length():
		out.append("- " + a[pi])
		pi += 1
	while pj < b.length():
		out.append("+ " + b[pj])
		pj += 1
	return out

fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) MergeOut:
	mo := matching(base, ours)
	mt := matching(base, theirs)
	var out = List[String]()
	var conflict = false
	var sb = 0
	var so = 0
	var st = 0
	for s in 0..(base.length() + 1):
		final := s == base.length()
		var eo = ours.length()
		var et = theirs.length()
		if not final:
			if mo[s] < 0 or mt[s] < 0: continue
			eo = mo[s]
			et = mt[s]
		bc := sub(base, sb, s)
		oc := sub(ours, so, eo)
		tc := sub(theirs, st, et)
		if oc == bc:
			for x in tc: out.append(x.clone())
		else if tc == bc:
			for x in oc: out.append(x.clone())
		else if oc == tc:
			for x in oc: out.append(x.clone())
		else:
			conflict = true
			out.append("<<<<<<< HEAD")
			for x in oc: out.append(x.clone())
			out.append("=======")
			for x in tc: out.append(x.clone())
			out.append(">>>>>>> " + branch)
		if not final:
			out.append(base[s].clone())
			sb = s + 1
			so = eo + 1
			st = et + 1
	return MergeOut(out, conflict)

fn valid_name(name: String) Bool:
	if name == "": return false
	var first = true
	for b in name.as_bytes().values():
		c := b.to_int()
		ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 46 or c == 95 or c == 47
		if first:
			if not ok: return false
		else:
			if not (ok or c == 45): return false
		first = false
	return true

fn all_digits(s: String) Bool:
	if s == "": return false
	for b in s.as_bytes().values():
		c := b.to_int()
		if c < 48 or c > 57: return false
	return true

fn is_lower_hex(s: String) Bool:
	for b in s.as_bytes().values():
		c := b.to_int()
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)): return false
	return true

fn short(id: String) String:
	return sl(id, 0, 7)

fn var Repo.emit(s: String) Unit:
	self.out.append(s)

fn Repo.head_id() Int:
	if self.head_branch == "": return self.head_detached
	return self.branches.get_or(self.head_branch, -1)

fn Repo.cid(i: Int) String: self.commits[i].id.clone()

fn Repo.short_of(i: Int) String: short(self.commits[i].id)

fn Repo.tree_of(i: Int) Map[String, String]:
	if i < 0: return Map[String, String]()
	return self.commits[i].tree.clone()

fn Repo.is_ancestor(a: Int, b: Int) Bool:
	// a is b or an ancestor of b
	var seen = Set[Int]()
	var stack = [b]
	while stack.length() > 0:
		x := stack[stack.length() - 1]
		stack.remove(-1)
		if x == a: return true
		if seen.contains(x): continue
		seen.add(x)
		for p in self.commits[x].parents:
			stack.append(p)
	return false

fn Repo.ancestors(b: Int) Set[Int]:
	var seen = Set[Int]()
	var stack = [b]
	while stack.length() > 0:
		x := stack[stack.length() - 1]
		stack.remove(-1)
		if seen.contains(x): continue
		seen.add(x)
		for p in self.commits[x].parents:
			stack.append(p)
	return seen

fn Repo.resolve(r: String) Int!:
	unknown := Error("unknown revision '{r}'")
	parts := r.split("~")
	if parts.length() > 2: return error(unknown)
	base := parts[0]
	var steps = 0
	if parts.length() == 2:
		if not all_digits(parts[1]): return error(unknown)
		steps = parts[1].parse_int().get(-1)
		if steps < 0: return error(unknown)
	var found = -1
	if base == "HEAD":
		found = self.head_id()
		if found < 0: return error(unknown)
	else:
		b := self.branches.get_or(base, -1)
		if b >= 0:
			found = b
		else if t := self.tags.get(base):
			found = t
		else if base.length() >= 4 and is_lower_hex(base):
			var count = 0
			for i in 0..self.commits.length():
				if self.commits[i].id.starts_with(base):
					count += 1
					found = i
			if count > 1: return error(Error("ambiguous revision '{r}'"))
	if found < 0: return error(unknown)
	for _k in 0..steps:
		ps := self.commits[found].parents
		if ps.length() == 0: return error(unknown)
		found = ps[0]
	return ok(found)

fn var Repo.make_commit(tree: Map[String, String], parents: List[Int], msg: String) Int:
	var text = "tree " + tree_hash(tree) + "\n"
	for p in parents:
		text = text + "parent " + self.commits[p].id + "\n"
	text = text + "\n" + msg + "\n"
	id := hash_hex(text)
	if i := self.ids.get(id): return i
	idx := self.commits.length()
	self.commits.append(Commit(id.clone(), parents.clone(), msg.clone(), tree.clone()))
	self.ids[id.clone()] = idx
	return idx

fn var Repo.move_head(i: Int) Unit:
	if self.head_branch == "":
		self.head_detached = i
	else:
		self.branches[self.head_branch.clone()] = i

fn Repo.branch_label() String:
	if self.head_branch == "": return "detached"
	return self.head_branch.clone()

fn Repo.dirty() Bool:
	h := self.tree_of(self.head_id())
	if not tree_eq(self.index, h): return true
	for name in self.index.keys():
		if w := self.work.get(name):
			if w != self.index.get_or(name, ""): return true
		else: return true
	return false

fn Repo.untracked_in(names: List[String]) String:
	for name in names.sorted():
		if self.work.contains(name) and not self.index.contains(name): return name
	return ""

fn var Repo.set_tree(t: Map[String, String]) Unit:
	for name in self.index.keys():
		self.work.remove(name.clone())
	for name in t.keys():
		self.work[name.clone()] = t.get_or(name, "")
	self.index = t.clone()

fn var Repo.reset_to(i: Int) Unit:
	oldh := self.tree_of(self.head_id())
	for name in self.index.keys():
		self.work.remove(name.clone())
	for name in oldh.keys():
		self.work.remove(name.clone())
	t := self.tree_of(i)
	for name in t.keys():
		self.work[name.clone()] = t.get_or(name, "")
	self.index = t.clone()
	self.move_head(i)
	self.conflicts = Map[String, String]()
	self.merging = false

fn var Repo.cmd_write(args: List[String], block: List[String], append: Bool) Unit:
	name := args[0]
	if append:
		old := self.work.get_or(name, "")
		self.work[name.clone()] = old + content_of(block)
	else:
		self.work[name.clone()] = content_of(block)

fn var Repo.cmd_rm(args: List[String]) Unit!:
	if args.length() == 0: return error(Error("usage: rm FILE..."))
	for a in args:
		if not self.work.contains(a): return error(Error("no such file: {a}"))
		self.work.remove(a.clone())
	return ok(unit)

fn var Repo.cmd_mv(args: List[String]) Unit!:
	if args.length() != 2: return error(Error("usage: mv OLD NEW"))
	c := self.work.get(args[0])
	if c.is_none(): return error(Error("no such file: {args[0]}"))
	content := c.get("")
	self.work.remove(args[0].clone())
	self.work[args[1].clone()] = content
	return ok(unit)

fn var Repo.cmd_cat(args: List[String]) Unit!:
	if args.length() != 1: return error(Error("usage: cat FILE"))
	c := self.work.get(args[0])
	if c.is_none(): return error(Error("no such file: {args[0]}"))
	for l in lines_of(c.get("")):
		self.emit(l)
	return ok(unit)

fn var Repo.cmd_ls() Unit:
	if self.work.length() == 0:
		self.emit("(empty)")
		return
	for n in self.work.keys().sorted():
		self.emit(n)

fn var Repo.cmd_add(args: List[String]) Unit!:
	if args.length() == 0: return error(Error("usage: add PATH..."))
	for a in args:
		if a == ".":
			for name in self.work.keys():
				self.index[name.clone()] = self.work.get_or(name, "")
				self.conflicts.remove(name.clone())
			for name in self.index.keys().clone():
				if not self.work.contains(name):
					self.index.remove(name.clone())
					self.conflicts.remove(name.clone())
		else:
			if w := self.work.get(a):
				self.index[a.clone()] = w.clone()
				self.conflicts.remove(a.clone())
			else if self.index.contains(a):
				self.index.remove(a.clone())
				self.conflicts.remove(a.clone())
			else if self.conflicts.contains(a):
				self.conflicts.remove(a.clone())
			else:
				return error(Error("pathspec '{a}' did not match any files"))
	return ok(unit)

fn var Repo.cmd_status() Unit:
	if self.head_branch == "":
		self.emit("HEAD detached at " + self.short_of(self.head_detached))
	else:
		self.emit("On branch " + self.head_branch)
	if self.merging:
		self.emit("merging: " + self.merge_branch)
	h := self.tree_of(self.head_id())
	var staged = List[String]()
	var names = Set[String]()
	for n in h.keys(): names.add(n.clone())
	for n in self.index.keys(): names.add(n.clone())
	for n in names.values().sorted():
		if self.conflicts.contains(n): continue
		hv := h.get(n)
		iv := self.index.get(n)
		if hv.is_none():
			staged.append("  new file: " + n)
		else if iv.is_none():
			staged.append("  deleted: " + n)
		else if not opt_same(hv, iv):
			staged.append("  modified: " + n)
	var unstaged = List[String]()
	for n in self.index.keys().sorted():
		if self.conflicts.contains(n): continue
		if w := self.work.get(n):
			if w != self.index.get_or(n, ""): unstaged.append("  modified: " + n)
		else:
			unstaged.append("  deleted: " + n)
	var confl = List[String]()
	for n in self.conflicts.keys().sorted():
		confl.append("  unmerged: " + n)
	var untracked = List[String]()
	for n in self.work.keys().sorted():
		if self.index.contains(n) or self.conflicts.contains(n): continue
		untracked.append("  " + n)
	if staged.length() + unstaged.length() + confl.length() + untracked.length() == 0:
		self.emit("nothing to commit, working tree clean")
		return
	if staged.length() > 0:
		self.emit("staged:")
		for x in staged: self.emit(x)
	if unstaged.length() > 0:
		self.emit("unstaged:")
		for x in unstaged: self.emit(x)
	if confl.length() > 0:
		self.emit("conflicts:")
		for x in confl: self.emit(x)
	if untracked.length() > 0:
		self.emit("untracked:")
		for x in untracked: self.emit(x)

fn var Repo.cmd_commit(msg: String) Unit!:
	if msg == "": return error(Error("empty commit message"))
	if self.conflicts.length() > 0:
		return error(Error("unresolved conflicts: " + self.conflicts.keys().sorted().join(" ")))
	cur := self.head_id()
	if self.merging:
		i := self.make_commit(self.index.clone(), [cur, self.merge_other], msg)
		self.move_head(i)
		self.merging = false
		self.merge_other = -1
		self.emit("[{self.branch_label()} {self.short_of(i)}] {msg}")
		return ok(unit)
	if tree_eq(self.index, self.tree_of(cur)): return error(Error("nothing to commit"))
	var parents = List[Int]()
	if cur >= 0: parents.append(cur)
	i := self.make_commit(self.index.clone(), parents, msg)
	self.move_head(i)
	if cur < 0:
		self.emit("[{self.branch_label()} (root-commit) {self.short_of(i)}] {msg}")
	else:
		self.emit("[{self.branch_label()} {self.short_of(i)}] {msg}")
	return ok(unit)

fn var Repo.cmd_log(args: List[String]) Unit!:
	var limit = -1
	if args.length() == 2 and args[0] == "-n" and all_digits(args[1]):
		limit = args[1].parse_int().get(0)
	else if args.length() != 0:
		return error(Error("usage: log [-n N]"))
	h := self.head_id()
	if h < 0:
		self.emit("no commits yet")
		return ok(unit)
	anc := self.ancestors(h).values().sorted()
	var count = 0
	var k = anc.length() - 1
	while k >= 0:
		if limit >= 0 and count >= limit: break
		c := anc[k]
		ps := self.commits[c].parents.clone()
		var line = self.short_of(c) + " " + self.commits[c].msg
		if ps.length() == 2:
			line = line + " (merge " + self.short_of(ps[0]) + " " + self.short_of(ps[1]) + ")"
		self.emit(line)
		count += 1
		k -= 1
	return ok(unit)

fn var Repo.diff_trees(a: Map[String, String], b: Map[String, String]) Unit:
	var names = Set[String]()
	for n in a.keys(): names.add(n.clone())
	for n in b.keys(): names.add(n.clone())
	var any = false
	for n in names.values().sorted():
		av := a.get(n)
		bv := b.get(n)
		if opt_same(av, bv): continue
		any = true
		self.emit("diff " + n)
		if av.is_none(): self.emit("new file")
		if bv.is_none(): self.emit("deleted file")
		for l in diff_lines(lines_of(av.get("")), lines_of(bv.get("") )):
			self.emit(l)
	if not any: self.emit("(no differences)")

fn var Repo.cmd_diff(args: List[String]) Unit!:
	if args.length() > 2: return error(Error("usage: diff [REF [REF]]"))
	if args.length() == 0:
		self.diff_trees(self.index.clone(), self.work.clone())
	else if args.length() == 1:
		i := self.resolve(args[0])?
		self.diff_trees(self.tree_of(i), self.work.clone())
	else:
		i := self.resolve(args[0])?
		j := self.resolve(args[1])?
		self.diff_trees(self.tree_of(i), self.tree_of(j))
	return ok(unit)

fn var Repo.cmd_branch(args: List[String]) Unit!:
	if args.length() == 0:
		if self.head_branch == "":
			self.emit("* (HEAD detached at " + self.short_of(self.head_detached) + ")")
		for n in self.branches.keys().sorted():
			if n == self.head_branch:
				self.emit("* " + n)
			else:
				self.emit("  " + n)
		return ok(unit)
	if args.length() == 2 and args[0] == "-d":
		n := args[1]
		if not self.branches.contains(n): return error(Error("branch '{n}' not found"))
		if n == self.head_branch: return error(Error("cannot delete the current branch '{n}'"))
		c := self.branches.get_or(n, -1)
		h := self.head_id()
		if h < 0 or not self.is_ancestor(c, h): return error(Error("branch '{n}' is not fully merged"))
		self.branches.remove(n.clone())
		self.emit("Deleted branch {n} (was {self.short_of(c)}).")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: branch [NAME | -d NAME]"))
	self.create_branch(args[0])?
	return ok(unit)

fn var Repo.create_branch(n: String) Unit!:
	if not valid_name(n): return error(Error("invalid branch name '{n}'"))
	if self.branches.contains(n): return error(Error("branch '{n}' already exists"))
	h := self.head_id()
	if h < 0: return error(Error("no commits yet"))
	self.branches[n.clone()] = h
	return ok(unit)

fn var Repo.cmd_tag(args: List[String]) Unit!:
	if args.length() == 0:
		for n in self.tags.keys().sorted():
			self.emit(n)
		return ok(unit)
	if args.length() > 2: return error(Error("usage: tag [NAME [REF]]"))
	n := args[0]
	if not valid_name(n): return error(Error("invalid tag name '{n}'"))
	if self.tags.contains(n): return error(Error("tag '{n}' already exists"))
	if args.length() == 1 or args[1] == "HEAD":
		if self.head_id() < 0: return error(Error("no commits yet"))
	var target = self.head_id()
	if args.length() == 2:
		target = self.resolve(args[1])?
	self.tags[n.clone()] = target
	return ok(unit)

fn var Repo.cmd_show(args: List[String]) Unit!:
	if args.length() != 1: return error(Error("usage: show REF"))
	i := self.resolve(args[0])?
	c := self.commits[i].tree.clone()
	self.emit("commit " + self.cid(i))
	self.emit("tree " + tree_hash(c))
	for p in self.commits[i].parents.clone():
		self.emit("parent " + self.cid(p))
	self.emit("message: " + self.commits[i].msg)
	self.emit("files:")
	for n in c.keys().sorted():
		self.emit("  " + n + " " + short(hash_hex(c.get_or(n, ""))))
	return ok(unit)

fn var Repo.cmd_checkout(args: List[String]) Unit!:
	if args.length() == 2 and args[0] == "-b":
		self.create_branch(args[1])?
		self.head_branch = args[1].clone()
		self.emit("Switched to a new branch '{args[1]}'")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: checkout REF | checkout -b NAME"))
	if self.merging: return error(Error("merge in progress"))
	t := args[0]
	if self.branches.contains(t):
		if t == self.head_branch:
			self.emit("Already on '{t}'")
			return ok(unit)
		c := self.branches.get_or(t, -1)
		if c < 0: return error(Error("unknown revision '{t}'"))
		self.checkout_commit(c)?
		self.head_branch = t.clone()
		self.emit("Switched to branch '{t}'")
		return ok(unit)
	c := self.resolve(t)?
	self.checkout_commit(c)?
	self.head_branch = ""
	self.head_detached = c
	self.emit("HEAD is now at {self.short_of(c)} {self.commits[c].msg}")
	return ok(unit)

fn var Repo.checkout_commit(c: Int) Unit!:
	if self.dirty(): return error(Error("local changes would be overwritten"))
	t := self.tree_of(c)
	u := self.untracked_in(t.keys())
	if u != "": return error(Error("untracked file would be overwritten: {u}"))
	self.set_tree(t)
	return ok(unit)

fn var Repo.cmd_reset(args: List[String]) Unit!:
	if args.length() < 1 or args.length() > 2 or args[0] != "--hard": return error(Error("usage: reset --hard [REF]"))
	var target = self.head_id()
	if args.length() == 2:
		target = self.resolve(args[1])?
	else if target < 0:
		return error(Error("no commits yet"))
	self.reset_to(target)
	self.emit("HEAD is now at {self.short_of(target)} {self.commits[target].msg}")
	return ok(unit)

fn var Repo.cmd_merge(args: List[String]) Unit!:
	if args.length() == 1 and args[0] == "--abort":
		if not self.merging: return error(Error("no merge in progress"))
		self.reset_to(self.head_id())
		self.emit("Merge aborted.")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: merge BRANCH"))
	bn := args[0]
	if self.merging: return error(Error("merge in progress"))
	cur := self.head_id()
	if cur < 0: return error(Error("no commits yet"))
	other := self.branches.get_or(bn, -1)
	if other < 0: return error(Error("unknown branch '{bn}'"))
	if self.dirty(): return error(Error("local changes would be overwritten"))
	if self.is_ancestor(other, cur):
		self.emit("Already up to date.")
		return ok(unit)
	if self.is_ancestor(cur, other):
		t := self.tree_of(other)
		u := self.untracked_in(t.keys())
		if u != "": return error(Error("untracked file would be overwritten: {u}"))
		self.set_tree(t)
		self.move_head(other)
		self.emit("Fast-forward")
		return ok(unit)
	ca := self.ancestors(cur)
	oa := self.ancestors(other)
	var base = -1
	for x in ca.values():
		if oa.contains(x) and x > base: base = x
	bt := self.tree_of(base)
	ot := self.tree_of(cur)
	tt := self.tree_of(other)
	var names = Set[String]()
	for n in bt.keys(): names.add(n.clone())
	for n in ot.keys(): names.add(n.clone())
	for n in tt.keys(): names.add(n.clone())
	var result = Map[String, String]()
	var overrides = Map[String, String]()
	var idx_keep = Map[String, String]()
	var confl = List[Chunk]()
	for n in names.values().sorted():
		b := bt.get(n)
		o := ot.get(n)
		t := tt.get(n)
		if opt_same(o, t):
			if v := o: result[n.clone()] = v.clone()
		else if opt_same(o, b):
			if v := t: result[n.clone()] = v.clone()
		else if opt_same(t, b):
			if v := o: result[n.clone()] = v.clone()
		else if o.is_none() or t.is_none():
			confl.append(Chunk(n.clone(), "modify/delete"))
			if v := o:
				overrides[n.clone()] = v.clone()
				idx_keep[n.clone()] = v.clone()
			else:
				overrides[n.clone()] = t.get("")
		else:
			m := merge3(lines_of(b.get("")), lines_of(o.get("")), lines_of(t.get("")), bn)
			if not m.conflict:
				result[n.clone()] = content_of(m.lines)
			else:
				kind := if b.is_some(): "content" else: "add/add"
				confl.append(Chunk(n.clone(), kind))
				overrides[n.clone()] = content_of(m.lines)
				idx_keep[n.clone()] = o.get("")
	var check = result.keys().clone()
	for n in overrides.keys(): check.append(n.clone())
	u := self.untracked_in(check)
	if u != "": return error(Error("untracked file would be overwritten: {u}"))
	for n in self.index.keys():
		if not result.contains(n): self.work.remove(n.clone())
	for n in result.keys():
		self.work[n.clone()] = result.get_or(n, "")
	for n in overrides.keys():
		self.work[n.clone()] = overrides.get_or(n, "")
	var newidx = result.clone()
	for n in idx_keep.keys():
		newidx[n.clone()] = idx_keep.get_or(n, "")
	self.index = newidx
	if confl.length() == 0:
		msg := "Merge branch '{bn}'"
		i := self.make_commit(result, [cur, other], msg)
		self.move_head(i)
		self.emit("Merge made by the 'three-way' strategy.")
		self.emit("[{self.branch_label()} {self.short_of(i)}] {msg}")
		return ok(unit)
	self.merging = true
	self.merge_other = other
	self.merge_branch = bn.clone()
	self.conflicts = Map[String, String]()
	for c in confl:
		self.conflicts[c.name.clone()] = c.kind.clone()
		if c.kind == "modify/delete":
			self.emit("CONFLICT (modify/delete): {c.name}")
		else:
			self.emit("CONFLICT ({c.kind}): Merge conflict in {c.name}")
	self.emit("Automatic merge failed; fix conflicts and then commit the result.")
	return ok(unit)

fn var Repo.run(cmd: String, args: List[String], rest: String, block: List[String]) Unit!:
	if cmd == "write" or cmd == "append":
		if args.length() != 1: return error(Error("usage: {cmd} FILE"))
		self.cmd_write(args, block, cmd == "append")
	else if cmd == "rm": self.cmd_rm(args)?
	else if cmd == "mv": self.cmd_mv(args)?
	else if cmd == "cat": self.cmd_cat(args)?
	else if cmd == "ls": self.cmd_ls()
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
	else if cmd == "reset": self.cmd_reset(args)?
	else: return error(Error("unknown command '{cmd}'"))
	return ok(unit)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	input := lines(stdin()) | collect(none)?
	var repo = Repo()
	var i = 0
	while i < input.length():
		raw := input[i]
		i += 1
		t := raw.trim()
		if t == "" or t.starts_with("#"): continue
		repo.emit("> " + raw.trim_end())
		fields := t.fields()
		cmd := fields[0]
		var args = List[String]()
		for k in 1..fields.length(): args.append(fields[k].clone())
		var rest = ""
		if cmd == "commit": rest = sl(t, 6, t.length()).trim()
		var block = List[String]()
		if (cmd == "write" or cmd == "append") and args.length() == 1:
			while i < input.length() and input[i] != ".":
				block.append(input[i].clone())
				i += 1
			i += 1
		r := repo.run(cmd, args, rest, block)
		if not r.is_ok():
			repo.emit("error: " + r.err().message)
	print(repo.out.join("\n"))
