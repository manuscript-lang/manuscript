import wrapping_multiply, bit_xor, bit_and, shift_right from "@std/math/math.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Commit:
	id: String
	parents: List[String]
	msg: String
	tree: Map[String, String]
	num: Int

type Repo:
	files: Map[String, String] = Map[String, String]()
	index: Map[String, String] = Map[String, String]()
	commits: Map[String, Commit] = Map[String, Commit]()
	branches: Map[String, String] = Map[String, String]()
	tags: Map[String, String] = Map[String, String]()
	head_branch: String = "main"
	detached: String = ""
	merging: Bool = false
	merge_other: String = ""
	merge_branch: String = ""
	conflicts: List[String] = List[String]()
	out: List[String] = List[String]()

type Merged:
	lines: List[String]
	conflict: Bool

fn fnv(s: String) Int:
	var h = -3750763034362895579
	bytes := s.to_bytes()
	for i in 0..bytes.length():
		b := bytes.get(i).to_int()
		h = wrapping_multiply(bit_xor(h, b), 1099511628211)
	return h

fn hex(h: Int) String:
	digits := "0123456789abcdef".chars()
	var s = ""
	var k = 15
	while k >= 0:
		nib := bit_and(shift_right(h, k * 4), 15)
		s = s + digits.get(nib, "0")
		k -= 1
	return s

fn short(id: String) String:
	if s := id.slice(0, 7):
		return s
	return id.clone()

fn lines_of(content: String) List[String]:
	var out = List[String]()
	if content.length() == 0: return out
	parts := content.split("\n")
	for i in 0..(parts.length() - 1):
		out.append(parts.get(i, "").clone())
	return out

fn content_of(lines: List[String]) String:
	var s = ""
	for l in lines:
		s = s + l + "\n"
	return s

fn tree_hash(t: Map[String, String]) String:
	var text = ""
	for n in t.keys().sorted():
		text = text + n + " " + hex(fnv(t.get_or(n, ""))) + "\n"
	return hex(fnv(text))

fn opt_eq(a: Map[String, String], b: Map[String, String], n: String) Bool:
	pa := a.contains(n)
	if pa != b.contains(n): return false
	if not pa: return true
	return a.get_or(n, "") == b.get_or(n, "")

fn tree_eq(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for k in a.keys():
		if not opt_eq(a, b, k): return false
	return true

fn match_of(a: List[String], b: List[String]) List[Int]:
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
			if a.get(i, "") == b.get(j, ""):
				l[i * w + j] = 1 + l.get(i * w + j + w + 1, 0)
			else:
				x := l.get(i * w + j + w, 0)
				y := l.get(i * w + j + 1, 0)
				l[i * w + j] = if x >= y: x else: y
			j -= 1
		i -= 1
	var res = List[Int]()
	for _k in 0..n:
		res.append(-1)
	i = 0
	var j = 0
	while i < n and j < m:
		if a.get(i, "") == b.get(j, ""):
			res[i] = j
			i += 1
			j += 1
		else if l.get(i * w + j + w, 0) >= l.get(i * w + j + 1, 0):
			i += 1
		else:
			j += 1
	return res

fn diff_lines(a: List[String], b: List[String]) List[String]:
	m := match_of(a, b)
	var out = List[String]()
	var pi = 0
	var pj = 0
	for i in 0..a.length():
		mj := m.get(i, -1)
		if mj < 0: continue
		while pi < i:
			out.append("- " + a.get(pi, ""))
			pi += 1
		while pj < mj:
			out.append("+ " + b.get(pj, ""))
			pj += 1
		out.append("  " + a.get(i, ""))
		pi = i + 1
		pj = mj + 1
	while pi < a.length():
		out.append("- " + a.get(pi, ""))
		pi += 1
	while pj < b.length():
		out.append("+ " + b.get(pj, ""))
		pj += 1
	return out

fn slice_lines(l: List[String], from: Int, to: Int) List[String]:
	var out = List[String]()
	var i = from
	while i < to:
		out.append(l.get(i, "").clone())
		i += 1
	return out

fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) Merged:
	mo := match_of(base, ours)
	mt := match_of(base, theirs)
	var out = List[String]()
	var conflict = false
	var pb = -1
	var po = -1
	var pt = -1
	for s in 0..(base.length() + 1):
		var ob = s
		var oo = ours.length()
		var ot = theirs.length()
		final := s == base.length()
		if not final:
			if mo.get(s, -1) < 0 or mt.get(s, -1) < 0: continue
			oo = mo.get(s, -1)
			ot = mt.get(s, -1)
		cb := slice_lines(base, pb + 1, ob)
		co := slice_lines(ours, po + 1, oo)
		ct := slice_lines(theirs, pt + 1, ot)
		if co == cb:
			for l in ct: out.append(l.clone())
		else if ct == cb:
			for l in co: out.append(l.clone())
		else if co == ct:
			for l in co: out.append(l.clone())
		else:
			conflict = true
			out.append("<<<<<<< HEAD")
			for l in co: out.append(l.clone())
			out.append("=======")
			for l in ct: out.append(l.clone())
			out.append(">>>>>>> " + branch)
		if not final:
			out.append(base.get(s, "").clone())
		pb = ob
		po = oo
		pt = ot
	return Merged(out, conflict)

fn valid_name(n: String) Bool:
	if n.length() == 0: return false
	cs := n.chars()
	for i in 0..cs.length():
		c := cs.get(i, "")
		ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "." or c == "_" or c == "/"
		if ok: continue
		if c == "-" and i > 0: continue
		return false
	return true

fn is_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not (c >= "0" and c <= "9"): return false
	return true

fn is_hex_prefix(s: String) Bool:
	if s.length() < 4: return false
	for c in s.chars():
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")): return false
	return true


fn Repo.head_id() String:
	if self.head_branch != "": return self.branches.get_or(self.head_branch, "")
	return self.detached.clone()

fn Repo.tree_of(id: String) Map[String, String]:
	var t = Map[String, String]()
	if c := self.commits.get(id):
		for e in c.tree.entries():
			t[e.key.clone()] = e.value.clone()
	return t

fn Repo.parents_of(id: String) List[String]:
	var ps = List[String]()
	if c := self.commits.get(id):
		for p in c.parents: ps.append(p.clone())
	return ps

fn Repo.msg_of(id: String) String:
	if c := self.commits.get(id):
		return c.msg.clone()
	return ""

fn Repo.num_of(id: String) Int:
	if c := self.commits.get(id):
		return c.num
	return 0

fn Repo.ancestors(id: String) Set[String]:
	var seen = Set[String]()
	var stack = List[String]()
	stack.append(id.clone())
	while stack.length() > 0:
		cur := stack.pop().get("")
		if cur == "" or seen.contains(cur): continue
		seen.add(cur.clone())
		for p in self.parents_of(cur):
			stack.append(p.clone())
	return seen

fn Repo.resolve(rv: String) String!:
	unknown := Error("unknown revision '{rv}'")
	parts := rv.split("~")
	if parts.length() > 2: return error(unknown)
	base := parts.get(0, "")
	var steps = 0
	if parts.length() == 2:
		ns := parts.get(1, "")
		if not is_digits(ns): return error(unknown)
		n := ns.parse_int()
		if n.is_none(): return error(unknown)
		steps = n.get(0)
	var id = ""
	if base == "HEAD":
		id = self.head_id()
		if id == "": return error(unknown)
	else:
		bid := self.branches.get_or(base, "")
		if bid != "":
			id = bid
		else if self.tags.contains(base):
			id = self.tags.get_or(base, "")
		else if is_hex_prefix(base):
			var found = List[String]()
			for k in self.commits.keys():
				if k.starts_with(base): found.append(k.clone())
			if found.length() > 1: return error(Error("ambiguous revision '{rv}'"))
			if found.length() == 1: id = found.get(0, "")
		if id == "": return error(unknown)
	var k = 0
	while k < steps:
		ps := self.parents_of(id)
		if ps.length() == 0: return error(unknown)
		id = ps.get(0, "")
		k += 1
	return ok(id)

fn var Repo.make_commit(tree: Map[String, String], parents: List[String], msg: String) String:
	var text = "tree " + tree_hash(tree) + "\n"
	for p in parents:
		text = text + "parent " + p + "\n"
	text = text + "\n" + msg + "\n"
	id := hex(fnv(text))
	if not self.commits.contains(id):
		var ps = List[String]()
		for p in parents: ps.append(p.clone())
		self.commits[id.clone()] = Commit(id.clone(), ps, msg.clone(), tree.clone(), self.commits.length() + 1)
	return id

fn var Repo.set_head(id: String) Unit:
	if self.head_branch != "":
		self.branches[self.head_branch.clone()] = id.clone()
	else:
		self.detached = id.clone()

fn Repo.dirty() Bool:
	if not tree_eq(self.index, self.tree_of(self.head_id())): return true
	for e in self.index.entries():
		if not self.files.contains(e.key): return true
		if self.files.get_or(e.key, "") != e.value: return true
	return false

fn Repo.check_untracked(target: Map[String, String]) Unit!:
	for n in target.keys().sorted():
		if not self.index.contains(n) and self.files.contains(n):
			return error(Error("untracked file would be overwritten: {n}"))
	return ok(unit)

fn var Repo.apply_tree(target: Map[String, String]) Unit:
	for k in self.index.clone().keys():
		self.files.remove(k.clone())
	for e in target.entries():
		self.files[e.key.clone()] = e.value.clone()
	self.index = target.clone()

fn Repo.branch_label() String:
	if self.head_branch != "": return self.head_branch.clone()
	return "detached"

fn var Repo.add_out(s: String) Unit:
	self.out.append(s)

fn var Repo.cmd_write(args: List[String], content: String, append: Bool) Unit!:
	name := args.get(0, "")
	if append and self.files.contains(name):
		self.files[name.clone()] = self.files.get_or(name, "") + content
	else:
		self.files[name.clone()] = content.clone()
	return ok(unit)

fn var Repo.cmd_rm(args: List[String]) Unit!:
	if args.length() == 0: return error(Error("usage: rm FILE..."))
	for a in args:
		if not self.files.contains(a): return error(Error("no such file: {a}"))
		self.files.remove(a)
	return ok(unit)

fn var Repo.cmd_mv(args: List[String]) Unit!:
	if args.length() != 2: return error(Error("usage: mv OLD NEW"))
	old := args.get(0, "")
	nw := args.get(1, "")
	if not self.files.contains(old): return error(Error("no such file: {old}"))
	c := self.files.get_or(old, "")
	self.files.remove(old)
	self.files[nw.clone()] = c.clone()
	return ok(unit)

fn var Repo.cmd_cat(args: List[String]) Unit!:
	if args.length() != 1: return error(Error("usage: cat FILE"))
	name := args.get(0, "")
	if not self.files.contains(name): return error(Error("no such file: {name}"))
	for l in lines_of(self.files.get_or(name, "")):
		self.add_out(l)
	return ok(unit)

fn var Repo.cmd_ls(args: List[String]) Unit!:
	if self.files.length() == 0:
		self.add_out("(empty)")
	else:
		for n in self.files.keys().sorted():
			self.add_out(n)
	return ok(unit)

fn var Repo.unconflict(n: String) Unit:
	var rest = List[String]()
	for c in self.conflicts:
		if c != n: rest.append(c.clone())
	self.conflicts = rest

fn var Repo.cmd_add(args: List[String]) Unit!:
	if args.length() == 0: return error(Error("usage: add PATH..."))
	for a in args:
		if a == ".":
			for e in self.files.clone().entries():
				self.index[e.key.clone()] = e.value.clone()
				self.unconflict(e.key)
			for k in self.index.clone().keys():
				if not self.files.contains(k):
					self.index.remove(k.clone())
					self.unconflict(k)
		else if self.files.contains(a):
			self.index[a.clone()] = self.files.get_or(a, "").clone()
			self.unconflict(a)
		else if self.index.contains(a):
			self.index.remove(a.clone())
			self.unconflict(a)
		else if self.conflicts.contains(a):
			self.unconflict(a)
		else:
			return error(Error("pathspec '{a}' did not match any files"))
	return ok(unit)

fn var Repo.cmd_status(args: List[String]) Unit!:
	if self.head_branch != "":
		self.add_out("On branch " + self.head_branch)
	else:
		self.add_out("HEAD detached at " + short(self.detached))
	if self.merging: self.add_out("merging: " + self.merge_branch)
	ht := self.tree_of(self.head_id())
	var staged = List[String]()
	var names = Set[String]()
	for k in ht.keys(): names.add(k.clone())
	for k in self.index.keys(): names.add(k.clone())
	for n in names.values().sorted():
		if self.conflicts.contains(n): continue
		inh := ht.contains(n)
		ini := self.index.contains(n)
		if ini and not inh: staged.append("new file: " + n)
		else if inh and not ini: staged.append("deleted: " + n)
		else if ht.get_or(n, "") != self.index.get_or(n, ""): staged.append("modified: " + n)
	var unstaged = List[String]()
	for n in self.index.keys().sorted():
		if self.conflicts.contains(n): continue
		if not self.files.contains(n): unstaged.append("deleted: " + n)
		else if self.files.get_or(n, "") != self.index.get_or(n, ""): unstaged.append("modified: " + n)
	var confl = List[String]()
	for n in self.conflicts.sorted(): confl.append("unmerged: " + n)
	var untracked = List[String]()
	for n in self.files.keys().sorted():
		if not self.index.contains(n) and not self.conflicts.contains(n): untracked.append(n.clone())
	if staged.length() + unstaged.length() + confl.length() + untracked.length() == 0:
		self.add_out("nothing to commit, working tree clean")
		return ok(unit)
	if staged.length() > 0:
		self.add_out("staged:")
		for s in staged: self.add_out("  " + s)
	if unstaged.length() > 0:
		self.add_out("unstaged:")
		for s in unstaged: self.add_out("  " + s)
	if confl.length() > 0:
		self.add_out("conflicts:")
		for s in confl: self.add_out("  " + s)
	if untracked.length() > 0:
		self.add_out("untracked:")
		for s in untracked: self.add_out("  " + s)
	return ok(unit)

fn var Repo.cmd_commit(msg: String) Unit!:
	if msg.length() == 0: return error(Error("empty commit message"))
	if self.conflicts.length() > 0:
		return error(Error("unresolved conflicts: " + self.conflicts.sorted().join(" ")))
	cur := self.head_id()
	if self.merging:
		var ps = List[String]()
		ps.append(cur.clone())
		ps.append(self.merge_other.clone())
		id := self.make_commit(self.index.clone(), ps, msg)
		self.set_head(id)
		self.merging = false
		self.merge_other = ""
		self.merge_branch = ""
		self.add_out("[" + self.branch_label() + " " + short(id) + "] " + msg)
		return ok(unit)
	if tree_eq(self.index, self.tree_of(cur)): return error(Error("nothing to commit"))
	var ps = List[String]()
	if cur != "": ps.append(cur.clone())
	id := self.make_commit(self.index.clone(), ps, msg)
	self.set_head(id)
	if cur == "":
		self.add_out("[" + self.branch_label() + " (root-commit) " + short(id) + "] " + msg)
	else:
		self.add_out("[" + self.branch_label() + " " + short(id) + "] " + msg)
	return ok(unit)

fn var Repo.cmd_log(args: List[String]) Unit!:
	var limit = -1
	if args.length() != 0:
		if args.length() != 2 or args.get(0, "") != "-n" or not is_digits(args.get(1, "")):
			return error(Error("usage: log [-n N]"))
		n := args.get(1, "").parse_int()
		if n.is_none(): return error(Error("usage: log [-n N]"))
		limit = n.get(0)
	head := self.head_id()
	if head == "": return error(Error("no commits yet"))
	ids := self.ancestors(head).values().sorted(fn a, b: self.num_of(b) - self.num_of(a))
	var count = 0
	for id in ids:
		if limit >= 0 and count >= limit: break
		count += 1
		ps := self.parents_of(id)
		var line = short(id) + " " + self.msg_of(id)
		if ps.length() == 2:
			line = line + " (merge " + short(ps.get(0, "")) + " " + short(ps.get(1, "")) + ")"
		self.add_out(line)
	return ok(unit)

fn var Repo.file_diff(name: String, l: Map[String, String], r: Map[String, String]) Unit:
	if opt_eq(l, r, name): return
	self.add_out("diff " + name)
	if not l.contains(name): self.add_out("new file")
	else if not r.contains(name): self.add_out("deleted file")
	for s in diff_lines(lines_of(l.get_or(name, "")), lines_of(r.get_or(name, ""))):
		self.add_out(s)

fn var Repo.cmd_diff(args: List[String]) Unit!:
	if args.length() > 2: return error(Error("usage: diff [REF [REF]]"))
	var left = Map[String, String]()
	var right = Map[String, String]()
	if args.length() == 0:
		left = self.index.clone()
		right = self.files.clone()
	else if args.length() == 1:
		id := self.resolve(args.get(0, ""))?
		left = self.tree_of(id)
		right = self.files.clone()
	else:
		id1 := self.resolve(args.get(0, ""))?
		id2 := self.resolve(args.get(1, ""))?
		left = self.tree_of(id1)
		right = self.tree_of(id2)
	var names = Set[String]()
	for k in left.keys(): names.add(k.clone())
	for k in right.keys(): names.add(k.clone())
	before := self.out.length()
	for n in names.values().sorted():
		self.file_diff(n, left, right)
	if self.out.length() == before: self.add_out("(no differences)")
	return ok(unit)

fn var Repo.cmd_branch(args: List[String]) Unit!:
	if args.length() == 0:
		if self.head_branch == "":
			self.add_out("* (HEAD detached at " + short(self.detached) + ")")
		for n in self.branches.keys().sorted():
			if n == self.head_branch: self.add_out("* " + n)
			else: self.add_out("  " + n)
		return ok(unit)
	if args.length() == 2 and args.get(0, "") == "-d":
		name := args.get(1, "")
		if not self.branches.contains(name): return error(Error("branch '{name}' not found"))
		if name == self.head_branch: return error(Error("cannot delete the current branch '{name}'"))
		id := self.branches.get_or(name, "")
		if id == "" or not self.ancestors(self.head_id()).contains(id):
			return error(Error("branch '{name}' is not fully merged"))
		self.branches.remove(name.clone())
		self.add_out("Deleted branch {name} (was " + short(id) + ").")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: branch [NAME | -d NAME]"))
	name := args.get(0, "")
	if not valid_name(name): return error(Error("invalid branch name '{name}'"))
	if self.branches.contains(name): return error(Error("branch '{name}' already exists"))
	head := self.head_id()
	if head == "": return error(Error("no commits yet"))
	self.branches[name.clone()] = head.clone()
	return ok(unit)

fn var Repo.cmd_tag(args: List[String]) Unit!:
	if args.length() == 0:
		for n in self.tags.keys().sorted(): self.add_out(n)
		return ok(unit)
	if args.length() > 2: return error(Error("usage: tag [NAME [REF]]"))
	name := args.get(0, "")
	if not valid_name(name): return error(Error("invalid tag name '{name}'"))
	if self.tags.contains(name): return error(Error("tag '{name}' already exists"))
	var id = ""
	if args.length() == 1 or args.get(1, "") == "HEAD":
		id = self.head_id()
		if id == "": return error(Error("no commits yet"))
	else:
		id = self.resolve(args.get(1, ""))?
	self.tags[name.clone()] = id.clone()
	return ok(unit)

fn var Repo.cmd_show(args: List[String]) Unit!:
	if args.length() != 1: return error(Error("usage: show REF"))
	id := self.resolve(args.get(0, ""))?
	t := self.tree_of(id)
	self.add_out("commit " + id)
	self.add_out("tree " + tree_hash(t))
	for p in self.parents_of(id): self.add_out("parent " + p)
	self.add_out("message: " + self.msg_of(id))
	self.add_out("files:")
	for n in t.keys().sorted():
		self.add_out("  " + n + " " + hex(fnv(t.get_or(n, ""))).slice(0, 7).get(""))
	return ok(unit)

fn var Repo.cmd_checkout(args: List[String]) Unit!:
	if args.length() == 2 and args.get(0, "") == "-b":
		name := args.get(1, "")
		if not valid_name(name): return error(Error("invalid branch name '{name}'"))
		if self.branches.contains(name): return error(Error("branch '{name}' already exists"))
		head := self.head_id()
		if head == "": return error(Error("no commits yet"))
		self.branches[name.clone()] = head.clone()
		self.head_branch = name.clone()
		self.detached = ""
		self.add_out("Switched to a new branch '{name}'")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: checkout REF | checkout -b NAME"))
	if self.merging: return error(Error("merge in progress"))
	target := args.get(0, "")
	if self.branches.contains(target):
		if target == self.head_branch:
			self.add_out("Already on '{target}'")
			return ok(unit)
		id := self.branches.get_or(target, "")
		t := self.tree_of(id)
		if self.dirty(): return error(Error("local changes would be overwritten"))
		self.check_untracked(t)?
		self.apply_tree(t)
		self.head_branch = target.clone()
		self.detached = ""
		self.add_out("Switched to branch '{target}'")
		return ok(unit)
	id := self.resolve(target)?
	t := self.tree_of(id)
	if self.dirty(): return error(Error("local changes would be overwritten"))
	self.check_untracked(t)?
	self.apply_tree(t)
	self.head_branch = ""
	self.detached = id.clone()
	self.add_out("HEAD is now at " + short(id) + " " + self.msg_of(id))
	return ok(unit)

fn var Repo.reset_hard(id: String) Unit:
	var old = Set[String]()
	for k in self.index.keys(): old.add(k.clone())
	for k in self.tree_of(self.head_id()).keys(): old.add(k.clone())
	for k in old.values(): self.files.remove(k.clone())
	t := self.tree_of(id)
	for e in t.entries():
		self.files[e.key.clone()] = e.value.clone()
	self.index = t.clone()
	self.set_head(id)
	self.merging = false
	self.merge_other = ""
	self.merge_branch = ""
	self.conflicts = List[String]()

fn var Repo.cmd_reset(args: List[String]) Unit!:
	if args.length() == 0 or args.length() > 2 or args.get(0, "") != "--hard":
		return error(Error("usage: reset --hard [REF]"))
	var id = ""
	if args.length() == 1:
		id = self.head_id()
		if id == "": return error(Error("no commits yet"))
	else:
		id = self.resolve(args.get(1, ""))?
	self.reset_hard(id)
	self.add_out("HEAD is now at " + short(id) + " " + self.msg_of(id))
	return ok(unit)

fn var Repo.cmd_merge(args: List[String]) Unit!:
	if args.length() == 1 and args.get(0, "") == "--abort":
		if not self.merging: return error(Error("no merge in progress"))
		self.reset_hard(self.head_id())
		self.add_out("Merge aborted.")
		return ok(unit)
	if args.length() != 1: return error(Error("usage: merge BRANCH"))
	branch := args.get(0, "")
	if self.merging: return error(Error("merge in progress"))
	cur := self.head_id()
	if cur == "": return error(Error("no commits yet"))
	other := self.branches.get_or(branch, "")
	if other == "": return error(Error("unknown branch '{branch}'"))
	if self.dirty(): return error(Error("local changes would be overwritten"))
	anc_cur := self.ancestors(cur)
	anc_other := self.ancestors(other)
	if anc_cur.contains(other):
		self.add_out("Already up to date.")
		return ok(unit)
	if anc_other.contains(cur):
		t := self.tree_of(other)
		self.check_untracked(t)?
		self.apply_tree(t)
		self.set_head(other)
		self.add_out("Fast-forward")
		return ok(unit)
	var base_id = ""
	var best = 0
	for id in anc_cur.values():
		if anc_other.contains(id) and self.num_of(id) > best:
			best = self.num_of(id)
			base_id = id.clone()
	bt := self.tree_of(base_id)
	ot := self.tree_of(cur)
	tt := self.tree_of(other)
	var names = Set[String]()
	for k in bt.keys(): names.add(k.clone())
	for k in ot.keys(): names.add(k.clone())
	for k in tt.keys(): names.add(k.clone())
	var res = Map[String, String]()
	var wf = Map[String, String]()
	var cnames = List[String]()
	var cmsgs = List[String]()
	for n in names.values().sorted():
		if opt_eq(ot, tt, n):
			if ot.contains(n): res[n.clone()] = ot.get_or(n, "").clone()
		else if opt_eq(ot, bt, n):
			if tt.contains(n): res[n.clone()] = tt.get_or(n, "").clone()
		else if opt_eq(tt, bt, n):
			if ot.contains(n): res[n.clone()] = ot.get_or(n, "").clone()
		else if ot.contains(n) != tt.contains(n):
			if ot.contains(n):
				res[n.clone()] = ot.get_or(n, "").clone()
				wf[n.clone()] = ot.get_or(n, "").clone()
			else:
				wf[n.clone()] = tt.get_or(n, "").clone()
			cnames.append(n.clone())
			cmsgs.append("CONFLICT (modify/delete): {n}")
		else:
			m := merge3(lines_of(bt.get_or(n, "")), lines_of(ot.get_or(n, "")), lines_of(tt.get_or(n, "")), branch)
			if not m.conflict:
				res[n.clone()] = content_of(m.lines)
			else:
				res[n.clone()] = ot.get_or(n, "").clone()
				wf[n.clone()] = content_of(m.lines)
				cnames.append(n.clone())
				if bt.contains(n): cmsgs.append("CONFLICT (content): Merge conflict in {n}")
				else: cmsgs.append("CONFLICT (add/add): Merge conflict in {n}")
	var chk = Set[String]()
	for k in res.keys(): chk.add(k.clone())
	for k in wf.keys(): chk.add(k.clone())
	for n in chk.values().sorted():
		if not self.index.contains(n) and self.files.contains(n):
			return error(Error("untracked file would be overwritten: {n}"))
	for k in self.index.clone().keys():
		if not res.contains(k): self.files.remove(k.clone())
	for e in res.entries():
		self.files[e.key.clone()] = e.value.clone()
	for e in wf.entries():
		self.files[e.key.clone()] = e.value.clone()
	self.index = res.clone()
	if cnames.length() == 0:
		var ps = List[String]()
		ps.append(cur.clone())
		ps.append(other.clone())
		msg := "Merge branch '{branch}'"
		id := self.make_commit(res, ps, msg)
		self.set_head(id)
		self.add_out("Merge made by the 'three-way' strategy.")
		self.add_out("[" + self.branch_label() + " " + short(id) + "] " + msg)
		return ok(unit)
	self.merging = true
	self.merge_other = other.clone()
	self.merge_branch = branch.clone()
	self.conflicts = cnames.clone()
	for m in cmsgs: self.add_out(m)
	self.add_out("Automatic merge failed; fix conflicts and then commit the result.")
	return ok(unit)

fn var Repo.run(cmd: String, args: List[String], rest: String) Unit!:
	if cmd == "rm": return self.cmd_rm(args)
	if cmd == "mv": return self.cmd_mv(args)
	if cmd == "cat": return self.cmd_cat(args)
	if cmd == "ls": return self.cmd_ls(args)
	if cmd == "add": return self.cmd_add(args)
	if cmd == "status": return self.cmd_status(args)
	if cmd == "commit": return self.cmd_commit(rest)
	if cmd == "log": return self.cmd_log(args)
	if cmd == "diff": return self.cmd_diff(args)
	if cmd == "branch": return self.cmd_branch(args)
	if cmd == "tag": return self.cmd_tag(args)
	if cmd == "show": return self.cmd_show(args)
	if cmd == "checkout": return self.cmd_checkout(args)
	if cmd == "merge": return self.cmd_merge(args)
	if cmd == "reset": return self.cmd_reset(args)
	return error(Error("unknown command '{cmd}'"))

fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	var all = text.split("\n").clone()
	if all.length() > 0 and all.get(all.length() - 1, "") == "": all.pop()
	var repo = Repo()
	repo.branches["main"] = ""
	var i = 0
	while i < all.length():
		raw := all.get(i, "")
		i += 1
		line := raw.trim_end()
		tl := line.trim()
		if tl.length() == 0 or tl.starts_with("#"): continue
		repo.add_out("> " + line)
		toks := tl.fields()
		cmd := toks.get(0, "")
		args := slice_lines(toks, 1, toks.length())
		if cmd == "write" or cmd == "append":
			if args.length() != 1:
				repo.add_out("error: usage: " + cmd + " FILE")
				continue
			var content = ""
			while i < all.length():
				l := all.get(i, "")
				i += 1
				if l == ".": break
				content = content + l + "\n"
			repo.cmd_write(args, content, cmd == "append")?
			continue
		rest := tl.slice(cmd.length(), tl.length()).get("").trim()
		r := repo.run(cmd, args, rest)
		if not r.is_ok():
			repo.add_out("error: " + r.err().message)
	print(repo.out.join("\n"), end: "")
	if repo.out.length() > 0: print("")
