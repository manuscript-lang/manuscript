import wrapping_multiply, bit_xor, bit_and, shift_right_unsigned from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Commit:
	id: String
	parents: List[String]
	msg: String
	tree: Map[String, String]
	num: Int

type MergeOut:
	lines: List[String]
	conflict: Bool

fn fnv(text: String) String:
	var h = -3750763034362895579
	b := text.as_bytes()
	for i in 0..b.length():
		h = bit_xor(h, b.get(i).to_int())
		h = wrapping_multiply(h, 1099511628211)
	hi := shift_right_unsigned(h, 32)
	lo := bit_and(h, 4294967295)
	return hi.to_string_radix(16).pad_start(8, "0") + lo.to_string_radix(16).pad_start(8, "0")

fn skeys(m: Map[String, String]) List[String]:
	var ks = m.keys().clone()
	ks.sort()
	return ks

fn tree_hash(t: Map[String, String]) String:
	var s = ""
	for name in skeys(t):
		s = s + name + " " + fnv(t.get_or(name, "")) + "\n"
	return fnv(s)

fn to_lines(content: String) List[String]:
	var parts = content.split("\n").clone()
	if parts.length() > 0:
		parts.remove(parts.length() - 1)
	return parts

fn from_lines(lines: List[String]) String:
	var s = ""
	for l in lines:
		s = s + l + "\n"
	return s

fn trees_equal(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for name in a.keys().clone():
		if not b.contains(name): return false
		if a.get_or(name, "") != b.get_or(name, ""): return false
	return true

fn all_digits(s: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

fn is_hex(s: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")): return false
	return true

fn valid_name(s: String) Bool:
	if s.is_empty(): return false
	var first = true
	for c in s.chars():
		ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "." or c == "_" or c == "/"
		if first:
			if not ok: return false
		else:
			if not (ok or c == "-"): return false
		first = false
	return true

// For each index i of a, the matched index in b or -1.
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
				l[i * w + j] = if x > y: x else: y
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
	mp := match_pairs(a, b)
	var out = List[String]()
	var i = 0
	var j = 0
	for k in 0..a.length():
		if mp[k] < 0: continue
		t := mp[k]
		while i < k:
			out.append("- " + a[i])
			i += 1
		while j < t:
			out.append("+ " + b[j])
			j += 1
		out.append("  " + a[k])
		i = k + 1
		j = t + 1
	while i < a.length():
		out.append("- " + a[i])
		i += 1
	while j < b.length():
		out.append("+ " + b[j])
		j += 1
	return out

fn sub(xs: List[String], from: Int, to: Int) List[String]:
	var out = List[String]()
	var i = from
	while i < to:
		out.append(xs[i].clone())
		i += 1
	return out

fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) MergeOut:
	mo := match_pairs(base, ours)
	mt := match_pairs(base, theirs)
	var out = List[String]()
	var conflict = false
	var pb = -1
	var po = -1
	var pt = -1
	for i in 0..(base.length() + 1):
		final := i == base.length()
		if not final:
			if mo[i] < 0 or mt[i] < 0: continue
		bi := i
		oi := if final: ours.length() else: mo[i]
		ti := if final: theirs.length() else: mt[i]
		bc := sub(base, pb + 1, bi)
		oc := sub(ours, po + 1, oi)
		tc := sub(theirs, pt + 1, ti)
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
			out.append(base[i].clone())
		pb = bi
		po = oi
		pt = ti
	return MergeOut(out, conflict)

type Repo:
	work: Map[String, String] = Map[String, String]()
	index: Map[String, String] = Map[String, String]()
	commits: List[Commit] = List[Commit]()
	cidx: Map[String, Int] = Map[String, Int]()
	branches: Map[String, String] = Map[String, String]()
	tags: Map[String, String] = Map[String, String]()
	head_branch: String = "main"
	head_commit: String = ""
	merging: Bool = false
	merge_other: String = ""
	merge_branch: String = ""
	conflicts: Set[String] = Set[String]()
	out: List[String] = List[String]()

fn var Repo.say(s: String) Unit:
	self.out.append(s)

fn Repo.head_id() String:
	if self.head_branch != "":
		return self.branches.get_or(self.head_branch, "").clone()
	return self.head_commit.clone()

fn Repo.tree_of(id: String) Map[String, String]:
	if id == "": return Map[String, String]()
	return self.commits[self.cidx.get_or(id, 0)].tree.clone()

fn Repo.msg_of(id: String) String:
	return self.commits[self.cidx.get_or(id, 0)].msg.clone()

fn Repo.num_of(id: String) Int:
	return self.commits[self.cidx.get_or(id, 0)].num

fn Repo.parents_of(id: String) List[String]:
	return self.commits[self.cidx.get_or(id, 0)].parents.clone()

fn Repo.short(id: String) String:
	return id.view(0, 7).clone()

fn Repo.label() String:
	if self.head_branch != "": return self.head_branch.clone()
	return "detached"

fn Repo.ancestors(id: String) Set[String]:
	var seen = Set[String]()
	if id == "": return seen
	var stack = [id.clone()]
	while stack.length() > 0:
		cur := stack.get(stack.length() - 1, "")
		stack.remove(stack.length() - 1)
		if seen.contains(cur): continue
		seen.add(cur.clone())
		for p in self.parents_of(cur):
			stack.append(p.clone())
	return seen

fn Repo.resolve(rev: String) String!:
	bad := Error("unknown revision '{rev}'")
	parts := rev.split("~")
	if parts.length() > 2: return error(bad)
	base := parts.get(0, "")
	var steps = 0
	if parts.length() == 2:
		if not all_digits(parts.get(1, "")): return error(bad)
		steps = parts.get(1, "").parse_int().get(-1)
		if steps < 0: return error(bad)
	var id = ""
	if base == "HEAD":
		id = self.head_id()
		if id == "": return error(bad)
	else if self.branches.get_or(base, "") != "":
		id = self.branches.get_or(base, "")
	else if self.tags.contains(base):
		id = self.tags.get_or(base, "")
	else if base.length() >= 4 and is_hex(base):
		var found = List[String]()
		for c in self.commits:
			if c.id.starts_with(base): found.append(c.id.clone())
		if found.length() > 1: return error(Error("ambiguous revision '{rev}'"))
		if found.length() == 0: return error(bad)
		id = found[0].clone()
	else:
		return error(bad)
	for _s in 0..steps:
		ps := self.parents_of(id)
		if ps.length() == 0: return error(bad)
		id = ps[0].clone()
	return ok(id)

fn var Repo.make_commit(tree: Map[String, String], parents: List[String], msg: String) String:
	var text = "tree " + tree_hash(tree) + "\n"
	for p in parents:
		text = text + "parent " + p + "\n"
	text = text + "\n" + msg + "\n"
	id := fnv(text)
	if self.cidx.contains(id): return id
	n := self.commits.length()
	self.commits.append(Commit(id.clone(), parents.clone(), msg.clone(), tree.clone(), n + 1))
	self.cidx[id.clone()] = n
	return id

fn var Repo.move_head(id: String) Unit:
	if self.head_branch != "":
		self.branches[self.head_branch.clone()] = id.clone()
	else:
		self.head_commit = id.clone()

fn Repo.dirty() Bool:
	ht := self.tree_of(self.head_id())
	if not trees_equal(self.index, ht): return true
	for name in self.index.keys().clone():
		if not self.work.contains(name): return true
		if self.work.get_or(name, "") != self.index.get_or(name, ""): return true
	return false

fn Repo.untracked_check(names: List[String]) Unit!:
	var ns = names.clone()
	ns.sort()
	for name in ns:
		if self.work.contains(name) and not self.index.contains(name):
			return error(Error("untracked file would be overwritten: {name}"))
	return ok(unit)

fn var Repo.apply_tree(tree: Map[String, String]) Unit:
	for name in self.index.keys().clone():
		self.work.remove(name.clone())
	for name in tree.keys().clone():
		self.work[name.clone()] = tree.get_or(name, "")
	self.index = tree.clone()

fn var Repo.cmd_add(args: List[String]) Unit!:
	if args.length() == 0: return error(Error("usage: add PATH..."))
	for p in args:
		if p == ".":
			for name in self.work.keys().clone():
				self.index[name.clone()] = self.work.get_or(name, "")
				self.conflicts.remove(name.clone())
			for name in self.index.keys().clone():
				if not self.work.contains(name):
					self.index.remove(name.clone())
					self.conflicts.remove(name.clone())
		else if self.work.contains(p):
			self.index[p.clone()] = self.work.get_or(p, "")
			self.conflicts.remove(p.clone())
		else if self.index.contains(p):
			self.index.remove(p.clone())
			self.conflicts.remove(p.clone())
		else if self.conflicts.contains(p):
			self.conflicts.remove(p.clone())
		else:
			return error(Error("pathspec '{p}' did not match any files"))
	return ok(unit)

fn var Repo.finish_commit(msg: String, parents: List[String]) Unit:
	id := self.make_commit(self.index.clone(), parents, msg)
	self.move_head(id)

fn var Repo.cmd_commit(rest: String) Unit!:
	if rest.is_empty(): return error(Error("empty commit message"))
	if self.conflicts.length() > 0:
		var cs = List[String]()
		for c in self.conflicts: cs.append(c.clone())
		cs.sort()
		return error(Error("unresolved conflicts: " + cs.join(" ")))
	head := self.head_id()
	if self.merging:
		self.finish_commit(rest, [head.clone(), self.merge_other.clone()])
		self.merging = false
		self.say("[{self.label()} {self.short(self.head_id())}] {rest}")
		return ok(unit)
	if trees_equal(self.index, self.tree_of(head)): return error(Error("nothing to commit"))
	var parents = List[String]()
	if head != "": parents.append(head.clone())
	self.finish_commit(rest, parents)
	if head == "":
		self.say("[{self.label()} (root-commit) {self.short(self.head_id())}] {rest}")
	else:
		self.say("[{self.label()} {self.short(self.head_id())}] {rest}")
	return ok(unit)

fn var Repo.cmd_log(args: List[String]) Unit!:
	var limit = -1
	if args.length() == 2 and args[0] == "-n" and all_digits(args[1]):
		limit = args[1].parse_int().get(-1)
		if limit < 0: return error(Error("usage: log [-n N]"))
	else if args.length() != 0:
		return error(Error("usage: log [-n N]"))
	head := self.head_id()
	if head == "": return error(Error("no commits yet"))
	anc := self.ancestors(head)
	var count = 0
	var n = self.commits.length() - 1
	while n >= 0:
		if limit >= 0 and count >= limit: break
		c := self.commits[n].clone()
		if anc.contains(c.id):
			if c.parents.length() == 2:
				self.say("{self.short(c.id)} {c.msg} (merge {self.short(c.parents[0])} {self.short(c.parents[1])})")
			else:
				self.say("{self.short(c.id)} {c.msg}")
			count += 1
		n -= 1
	return ok(unit)

fn var Repo.emit_diff(left: Map[String, String], right: Map[String, String]) Unit:
	var names = Set[String]()
	for k in left.keys().clone(): names.add(k.clone())
	for k in right.keys().clone(): names.add(k.clone())
	var ns = List[String]()
	for k in names: ns.append(k.clone())
	ns.sort()
	var any = false
	for name in ns:
		l := left.contains(name)
		r := right.contains(name)
		if l and r and left.get_or(name, "") == right.get_or(name, ""): continue
		any = true
		self.say("diff {name}")
		if not l: self.say("new file")
		if not r: self.say("deleted file")
		for line in diff_lines(to_lines(left.get_or(name, "")), to_lines(right.get_or(name, ""))):
			self.say(line)
	if not any: self.say("(no differences)")

fn var Repo.cmd_diff(args: List[String]) Unit!:
	if args.length() > 2: return error(Error("usage: diff [REF [REF]]"))
	if args.length() == 0:
		self.emit_diff(self.index.clone(), self.work.clone())
	else if args.length() == 1:
		a := self.resolve(args[0])?
		self.emit_diff(self.tree_of(a), self.work.clone())
	else:
		a := self.resolve(args[0])?
		b := self.resolve(args[1])?
		self.emit_diff(self.tree_of(a), self.tree_of(b))
	return ok(unit)

fn var Repo.cmd_branch(args: List[String]) Unit!:
	if args.length() == 0:
		var names = List[String]()
		for k in self.branches.keys().clone(): names.append(k.clone())
		names.sort()
		if self.head_branch == "":
			self.say("* (HEAD detached at {self.short(self.head_commit)})")
		for n in names:
			if n == self.head_branch:
				self.say("* {n}")
			else:
				self.say("  {n}")
		return ok(unit)
	if args.length() == 2 and args[0] == "-d":
		name := args[1]
		if not self.branches.contains(name): return error(Error("branch '{name}' not found"))
		if name == self.head_branch: return error(Error("cannot delete the current branch '{name}'"))
		id := self.branches.get_or(name, "")
		if id == "" or not self.ancestors(self.head_id()).contains(id):
			return error(Error("branch '{name}' is not fully merged"))
		self.branches.remove(name.clone())
		self.say("Deleted branch {name} (was {self.short(id)}).")
		return ok(unit)
	if args.length() == 1:
		self.create_branch(args[0])?
		return ok(unit)
	return error(Error("usage: branch [NAME | -d NAME]"))

fn var Repo.create_branch(name: String) Unit!:
	if not valid_name(name): return error(Error("invalid branch name '{name}'"))
	if self.branches.contains(name): return error(Error("branch '{name}' already exists"))
	head := self.head_id()
	if head == "": return error(Error("no commits yet"))
	self.branches[name.clone()] = head
	return ok(unit)

fn var Repo.cmd_tag(args: List[String]) Unit!:
	if args.length() == 0:
		var names = List[String]()
		for k in self.tags.keys().clone(): names.append(k.clone())
		names.sort()
		for n in names: self.say(n)
		return ok(unit)
	if args.length() > 2: return error(Error("usage: tag [NAME [REF]]"))
	name := args[0]
	if not valid_name(name): return error(Error("invalid tag name '{name}'"))
	if self.tags.contains(name): return error(Error("tag '{name}' already exists"))
	rev := if args.length() == 2: args[1].clone() else: "HEAD"
	if (args.length() == 1 or rev == "HEAD") and self.head_id() == "":
		return error(Error("no commits yet"))
	id := self.resolve(rev)?
	self.tags[name.clone()] = id
	return ok(unit)

fn var Repo.cmd_show(args: List[String]) Unit!:
	if args.length() != 1: return error(Error("usage: show REF"))
	id := self.resolve(args[0])?
	tree := self.tree_of(id)
	self.say("commit {id}")
	self.say("tree {tree_hash(tree)}")
	for p in self.parents_of(id):
		self.say("parent {p}")
	self.say("message: {self.msg_of(id)}")
	self.say("files:")
	for name in skeys(tree):
		self.say("  {name} {fnv(tree.get_or(name, "")).view(0, 7)}")
	return ok(unit)

fn var Repo.cmd_checkout(args: List[String]) Unit!:
	if args.length() == 2 and args[0] == "-b":
		self.create_branch(args[1])?
		self.head_branch = args[1].clone()
		self.say("Switched to a new branch '{args[1]}'")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: checkout REF | checkout -b NAME"))
	if self.merging: return error(Error("merge in progress"))
	target := args[0]
	if self.branches.contains(target) and self.branches.get_or(target, "") != "":
		if target == self.head_branch:
			self.say("Already on '{target}'")
			return ok(unit)
		if self.dirty(): return error(Error("local changes would be overwritten"))
		id := self.branches.get_or(target, "")
		tree := self.tree_of(id)
		self.untracked_check(tree.keys())?
		self.apply_tree(tree)
		self.head_branch = target.clone()
		self.say("Switched to branch '{target}'")
		return ok(unit)
	if self.branches.contains(target):
		if target == self.head_branch:
			self.say("Already on '{target}'")
			return ok(unit)
	id := self.resolve(target)?
	if self.dirty(): return error(Error("local changes would be overwritten"))
	tree := self.tree_of(id)
	self.untracked_check(tree.keys())?
	self.apply_tree(tree)
	self.head_branch = ""
	self.head_commit = id.clone()
	self.say("HEAD is now at {self.short(id)} {self.msg_of(id)}")
	return ok(unit)

fn var Repo.do_reset(id: String) Unit:
	for name in self.index.keys().clone():
		self.work.remove(name.clone())
	for name in self.tree_of(self.head_id()).keys().clone():
		self.work.remove(name.clone())
	tree := self.tree_of(id)
	for name in tree.keys().clone():
		self.work[name.clone()] = tree.get_or(name, "")
	self.index = tree.clone()
	self.move_head(id)
	self.merging = false
	self.conflicts = Set[String]()

fn var Repo.cmd_reset(args: List[String]) Unit!:
	if args.length() == 0 or args.length() > 2 or args[0] != "--hard":
		return error(Error("usage: reset --hard [REF]"))
	var id = ""
	if args.length() == 1:
		id = self.head_id()
		if id == "": return error(Error("no commits yet"))
	else:
		id = self.resolve(args[1])?
	self.do_reset(id)
	self.say("HEAD is now at {self.short(id)} {self.msg_of(id)}")
	return ok(unit)

fn var Repo.cmd_status() Unit:
	if self.head_branch != "":
		self.say("On branch {self.head_branch}")
	else:
		self.say("HEAD detached at {self.short(self.head_commit)}")
	if self.merging: self.say("merging: {self.merge_branch}")
	ht := self.tree_of(self.head_id())
	var staged = List[String]()
	var names = Set[String]()
	for k in ht.keys().clone(): names.add(k.clone())
	for k in self.index.keys().clone(): names.add(k.clone())
	var ns = List[String]()
	for k in names: ns.append(k.clone())
	ns.sort()
	for n in ns:
		if self.conflicts.contains(n): continue
		inh := ht.contains(n)
		ini := self.index.contains(n)
		if ini and not inh:
			staged.append("new file: {n}")
		else if inh and not ini:
			staged.append("deleted: {n}")
		else if ht.get_or(n, "") != self.index.get_or(n, ""):
			staged.append("modified: {n}")
	var unstaged = List[String]()
	for n in skeys(self.index):
		if self.conflicts.contains(n): continue
		if not self.work.contains(n):
			unstaged.append("deleted: {n}")
		else if self.work.get_or(n, "") != self.index.get_or(n, ""):
			unstaged.append("modified: {n}")
	var confl = List[String]()
	for c in self.conflicts: confl.append("{c}")
	confl.sort()
	var cl = List[String]()
	for c in confl: cl.append("unmerged: {c}")
	var untracked = List[String]()
	for n in skeys(self.work):
		if not self.index.contains(n) and not self.conflicts.contains(n):
			untracked.append(n.clone())
	if staged.length() + unstaged.length() + cl.length() + untracked.length() == 0:
		self.say("nothing to commit, working tree clean")
		return
	if staged.length() > 0:
		self.say("staged:")
		for s in staged: self.say("  {s}")
	if unstaged.length() > 0:
		self.say("unstaged:")
		for s in unstaged: self.say("  {s}")
	if cl.length() > 0:
		self.say("conflicts:")
		for s in cl: self.say("  {s}")
	if untracked.length() > 0:
		self.say("untracked:")
		for s in untracked: self.say("  {s}")

fn var Repo.cmd_merge(args: List[String]) Unit!:
	if args.length() == 1 and args[0] == "--abort":
		if not self.merging: return error(Error("no merge in progress"))
		self.do_reset(self.head_id())
		self.say("Merge aborted.")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: merge BRANCH"))
	branch := args[0]
	if self.merging: return error(Error("merge in progress"))
	cur := self.head_id()
	if cur == "": return error(Error("no commits yet"))
	other := self.branches.get_or(branch, "")
	if other == "": return error(Error("unknown branch '{branch}'"))
	if self.dirty(): return error(Error("local changes would be overwritten"))
	cur_anc := self.ancestors(cur)
	if cur_anc.contains(other):
		self.say("Already up to date.")
		return ok(unit)
	other_anc := self.ancestors(other)
	if other_anc.contains(cur):
		tree := self.tree_of(other)
		self.untracked_check(tree.keys())?
		self.apply_tree(tree)
		self.move_head(other)
		self.say("Fast-forward")
		return ok(unit)
	var base_id = ""
	var best = 0
	for a in cur_anc:
		if other_anc.contains(a) and self.num_of(a) > best:
			best = self.num_of(a)
			base_id = a.clone()
	bt := self.tree_of(base_id)
	ot := self.tree_of(cur)
	tt := self.tree_of(other)
	var names = Set[String]()
	for k in bt.keys().clone(): names.add(k.clone())
	for k in ot.keys().clone(): names.add(k.clone())
	for k in tt.keys().clone(): names.add(k.clone())
	var ns = List[String]()
	for k in names: ns.append(k.clone())
	ns.sort()
	var idx = Map[String, String]()
	var wf = Map[String, String]()
	var kinds = Map[String, String]()
	for n in ns:
		ob := ot.contains(n)
		tb := tt.contains(n)
		bb := bt.contains(n)
		ov := ot.get_or(n, "")
		tv := tt.get_or(n, "")
		bv := bt.get_or(n, "")
		same_ot := ob == tb and ov == tv.clone()
		o_eq_b := ob == bb and ov == bv
		t_eq_b := tb == bb and tv == bv
		if same_ot:
			if ob: idx[n.clone()] = ov.clone()
		else if o_eq_b:
			if tb: idx[n.clone()] = tv.clone()
		else if t_eq_b:
			if ob: idx[n.clone()] = ov.clone()
		else if ob != tb:
			kinds[n.clone()] = "modify/delete"
			if ob:
				idx[n.clone()] = ov.clone()
				wf[n.clone()] = ov.clone()
			else:
				wf[n.clone()] = tv.clone()
		else:
			m := merge3(to_lines(bv), to_lines(ov), to_lines(tv), branch)
			if m.conflict:
				kinds[n.clone()] = if bb: "content" else: "add/add"
				idx[n.clone()] = ov.clone()
				wf[n.clone()] = from_lines(m.lines)
			else:
				idx[n.clone()] = from_lines(m.lines)
	var chk = idx.keys().clone()
	for k in wf.keys().clone(): chk.append(k.clone())
	self.untracked_check(chk)?
	for name in self.index.keys().clone():
		if not idx.contains(name): self.work.remove(name.clone())
	for name in idx.keys().clone():
		self.work[name.clone()] = idx.get_or(name, "")
	for name in wf.keys().clone():
		self.work[name.clone()] = wf.get_or(name, "")
	self.index = idx.clone()
	if kinds.length() == 0:
		msg := "Merge branch '{branch}'"
		id := self.make_commit(self.index.clone(), [cur.clone(), other.clone()], msg)
		self.move_head(id)
		self.say("Merge made by the 'three-way' strategy.")
		self.say("[{self.label()} {self.short(id)}] {msg}")
		return ok(unit)
	self.merging = true
	self.merge_other = other.clone()
	self.merge_branch = branch.clone()
	self.conflicts = Set[String]()
	for n in skeys(kinds):
		self.conflicts.add(n.clone())
		k := kinds.get_or(n, "")
		if k == "modify/delete":
			self.say("CONFLICT (modify/delete): {n}")
		else:
			self.say("CONFLICT ({k}): Merge conflict in {n}")
	self.say("Automatic merge failed; fix conflicts and then commit the result.")
	return ok(unit)

fn var Repo.dispatch(cmd: String, args: List[String], rest: String) Unit!:
	if cmd == "rm":
		if args.length() == 0: return error(Error("usage: rm FILE..."))
		for a in args:
			if not self.work.contains(a): return error(Error("no such file: {a}"))
			self.work.remove(a)
	else if cmd == "mv":
		if args.length() != 2: return error(Error("usage: mv OLD NEW"))
		if not self.work.contains(args[0]): return error(Error("no such file: {args[0]}"))
		if args[0] != args[1]:
			v := self.work.get_or(args[0], "")
			self.work.remove(args[0].clone())
			self.work[args[1].clone()] = v
	else if cmd == "cat":
		if args.length() != 1: return error(Error("usage: cat FILE"))
		if not self.work.contains(args[0]): return error(Error("no such file: {args[0]}"))
		for l in to_lines(self.work.get_or(args[0], "")): self.say(l)
	else if cmd == "ls":
		if self.work.length() == 0:
			self.say("(empty)")
		else:
			for n in skeys(self.work): self.say(n)
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
		return error(Error("unknown command '{cmd}'"))
	return ok(unit)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	raw := read_all(stdin(), none)?
	text := raw.decode_utf8().get("")
	var lines = text.split("\n").clone()
	if lines.length() > 0 and lines.get(lines.length() - 1, "x") == "":
		lines.remove(lines.length() - 1)
	var repo = Repo()
	var i = 0
	while i < lines.length():
		line := lines[i].trim()
		i += 1
		if line.is_empty() or line.starts_with("#"): continue
		repo.say("> {line}")
		norm := line.replace("\t", " ")
		var toks = List[String]()
		for t in norm.split(" "):
			if not t.is_empty(): toks.append(t.clone())
		cmd := toks[0].clone()
		toks.remove(0)
		rest := norm.view(cmd.length(), norm.length()).trim()
		if cmd == "write" or cmd == "append":
			if toks.length() != 1:
				repo.say("error: usage: {cmd} FILE")
				continue
			var content = ""
			while i < lines.length() and lines[i] != ".":
				content = content + lines[i] + "\n"
				i += 1
			i += 1
			name := toks[0]
			if cmd == "append":
				repo.work[name.clone()] = repo.work.get_or(name, "") + content
			else:
				repo.work[name.clone()] = content
			continue
		res := repo.dispatch(cmd, toks, rest)
		if res.is_error():
			repo.say("error: " + res.err().message)
	print(repo.out.join("\n"))
