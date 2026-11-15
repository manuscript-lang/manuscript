import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import bit_and, bit_xor, shift_right_unsigned, wrapping_multiply from "@std/math/math.ms"
import values from "@std/bytes.ms"

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
	order: List[String] = List[String]()
	branches: Map[String, String] = Map[String, String]()
	tags: Map[String, String] = Map[String, String]()
	head_branch: String = "main"
	head_commit: String = ""
	merging: Bool = false
	merge_other: String = ""
	merge_branch: String = ""
	conflicts: Set[String] = Set[String]()

fn fnv(s: String) Int:
	var h = -3750763034362895579
	for b in values(s.as_bytes()):
		h = bit_xor(h, b.to_int())
		h = wrapping_multiply(h, 1099511628211)
	return h

fn hex16(h: Int) String:
	digits := "0123456789abcdef"
	var out = ""
	for k in 0..16:
		d := bit_and(shift_right_unsigned(h, 4 * (15 - k)), 15)
		out = out + digits.slice(d, d + 1).get("")
	return out

fn hash_of(s: String) String: hex16(fnv(s))

fn short(id: String) String: id.slice(0, 7).get("")

fn sorted_keys(m: Map[String, String]) List[String]:
	var ks = m.keys().clone()
	ks.sort()
	return ks

fn tree_hash(t: Map[String, String]) String:
	var text = ""
	for name in sorted_keys(t):
		text = text + name + " " + hash_of(t.get_or(name, "")) + "\n"
	return hash_of(text)

fn trees_equal(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for e in a.entries():
		if v := b.get(e.key):
			if v != e.value: return false
		else:
			return false
	return true

fn same(a: String?, b: String?) Bool:
	if x := a:
		if y := b:
			return x == y
		return false
	return b.is_none()

fn split_lines(content: String) List[String]:
	var out = List[String]()
	if content.length() == 0: return out
	parts := content.split("\n", none)
	for i in 0..parts.length() - 1:
		out.append(parts.get(i, "").clone())
	return out

fn join_lines(ls: List[String]) String:
	var out = ""
	for l in ls:
		out = out + l + "\n"
	return out

fn range_of(xs: List[String], a: Int, b: Int) List[String]:
	var out = List[String]()
	var i = a
	while i < b:
		out.append(xs.get(i, "").clone())
		i += 1
	return out

fn lists_equal(a: List[String], b: List[String]) Bool:
	if a.length() != b.length(): return false
	for i in 0..a.length():
		if a.get(i, "") != b.get(i, ""): return false
	return true

// matching pairs: returns list of ai, bi flattened as two lists
type Pairs:
	a: List[Int]
	b: List[Int]

fn match_pairs(a: List[String], b: List[String]) Pairs:
	n := a.length()
	m := b.length()
	w := m + 1
	var l = List[Int]()
	for _i in 0..(n + 1) * w:
		l.append(0)
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a.get(i, "") == b.get(j, ""):
				l.replace(i * w + j, 1 + l.get(i * w + j + w + 1, 0))
			else:
				x := l.get(i * w + j + w, 0)
				y := l.get(i * w + j + 1, 0)
				l.replace(i * w + j, if x >= y: x else: y)
			j -= 1
		i -= 1
	var pa = List[Int]()
	var pb = List[Int]()
	var p = 0
	var q = 0
	while p < n and q < m:
		if a.get(p, "") == b.get(q, ""):
			pa.append(p)
			pb.append(q)
			p += 1
			q += 1
		else if l.get((p + 1) * w + q, 0) >= l.get(p * w + q + 1, 0):
			p += 1
		else:
			q += 1
	return Pairs(a: pa, b: pb)

fn line_diff(a: List[String], b: List[String]) List[String]:
	pr := match_pairs(a, b)
	var out = List[String]()
	var p = 0
	var q = 0
	for k in 0..pr.a.length():
		pa := pr.a.get(k, 0)
		pb := pr.b.get(k, 0)
		while p < pa:
			out.append("- " + a.get(p, ""))
			p += 1
		while q < pb:
			out.append("+ " + b.get(q, ""))
			q += 1
		out.append("  " + a.get(pa, ""))
		p = pa + 1
		q = pb + 1
	while p < a.length():
		out.append("- " + a.get(p, ""))
		p += 1
	while q < b.length():
		out.append("+ " + b.get(q, ""))
		q += 1
	return out

// returns merged lines; conflict flag via second element in result
type Merged:
	out: List[String]
	conflict: Bool

fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) Merged:
	po := match_pairs(base, ours)
	pt := match_pairs(base, theirs)
	n := base.length()
	var bo = List[Int]()
	var bt = List[Int]()
	for _i in 0..n:
		bo.append(-1)
		bt.append(-1)
	for k in 0..po.a.length():
		bo.replace(po.a.get(k, 0), po.b.get(k, 0))
	for k in 0..pt.a.length():
		bt.replace(pt.a.get(k, 0), pt.b.get(k, 0))
	var out = List[String]()
	var conflict = false
	var pb = -1
	var pos = -1
	var pts = -1
	for i in 0..n + 1:
		var oi = ours.length()
		var ti = theirs.length()
		if i < n:
			if bo.get(i, -1) < 0 or bt.get(i, -1) < 0: continue
			oi = bo.get(i, -1)
			ti = bt.get(i, -1)
		cb := range_of(base, pb + 1, i)
		co := range_of(ours, pos + 1, oi)
		ct := range_of(theirs, pts + 1, ti)
		if lists_equal(co, cb):
			for x in ct: out.append(x.clone())
		else if lists_equal(ct, cb):
			for x in co: out.append(x.clone())
		else if lists_equal(co, ct):
			for x in co: out.append(x.clone())
		else:
			conflict = true
			out.append("<<<<<<< HEAD")
			for x in co: out.append(x.clone())
			out.append("=======")
			for x in ct: out.append(x.clone())
			out.append(">>>>>>> " + branch)
		if i < n:
			out.append(base.get(i, "").clone())
		pb = i
		pos = oi
		pts = ti
	return Merged(out: out, conflict: conflict)

fn valid_name(name: String) Bool:
	if name.length() == 0: return false
	var first = true
	for c in name.chars():
		ok_c := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "." or c == "_" or c == "/"
		if first:
			if not ok_c: return false
		else:
			if not (ok_c or c == "-"): return false
		first = false
	return true

fn is_hex_prefix(s: String) Bool:
	if s.length() < 4: return false
	for c in s.chars():
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")): return false
	return true

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not (c >= "0" and c <= "9"): return false
	return true

fn Repo.cur() String:
	if self.head_branch.length() > 0:
		return self.branches.get_or(self.head_branch, "")
	return self.head_commit.clone()

fn Repo.tree_of(id: String) Map[String, String]:
	if id.length() == 0: return Map[String, String]()
	if c := self.commits.get(id):
		return c.tree.clone()
	return Map[String, String]()

fn Repo.parents_of(id: String) List[String]:
	if c := self.commits.get(id):
		return c.parents.clone()
	return List[String]()

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
	var stack = [id.clone()]
	while stack.length() > 0:
		x := stack.pop().get("")
		if x.length() == 0 or seen.contains(x): continue
		seen.add(x.clone())
		for p in self.parents_of(x):
			stack.append(p.clone())
	return seen

fn Repo.resolve(rv: String) String!:
	var base = rv.clone()
	var steps = 0
	if i := rv.index_of("~"):
		base = rv.slice(0, i).get("")
		n := rv.slice(i + 1, rv.length()).get("")
		if not all_digits(n): return error(Error("unknown revision '{rv}'"))
		if v := n.parse_int():
			steps = v
		else:
			return error(Error("unknown revision '{rv}'"))
	var id = ""
	if base == "HEAD":
		id = self.cur()
		if id.length() == 0: return error(Error("unknown revision '{rv}'"))
	else:
		b := self.branches.get_or(base, "")
		if b.length() > 0:
			id = b
		else if t := self.tags.get(base):
			id = t.clone()
		else if is_hex_prefix(base):
			var found = List[String]()
			for c in self.order:
				if c.starts_with(base): found.append(c.clone())
			if found.length() > 1: return error(Error("ambiguous revision '{rv}'"))
			if found.length() == 1: id = found.get(0, "").clone()
		if id.length() == 0: return error(Error("unknown revision '{rv}'"))
	for _i in 0..steps:
		ps := self.parents_of(id)
		if ps.length() == 0: return error(Error("unknown revision '{rv}'"))
		id = ps.get(0, "").clone()
	return ok(id)

fn var Repo.make_commit(tree: Map[String, String], parents: List[String], msg: String) String:
	var text = "tree " + tree_hash(tree) + "\n"
	for p in parents:
		text = text + "parent " + p + "\n"
	text = text + "\n" + msg + "\n"
	id := hash_of(text)
	if self.commits.contains(id): return id
	self.order.append(id.clone())
	self.commits[id.clone()] = Commit(id: id.clone(), parents: parents.clone(), msg: msg.clone(), tree: tree.clone(), num: self.order.length())
	return id

fn var Repo.move_head(id: String) Void:
	if self.head_branch.length() > 0:
		self.branches[self.head_branch.clone()] = id.clone()
	else:
		self.head_commit = id.clone()

fn Repo.dirty() Bool:
	if not trees_equal(self.index, self.tree_of(self.cur())): return true
	for e in self.index.entries():
		if w := self.files.get(e.key):
			if w != e.value: return true
		else:
			return true
	return false

fn Repo.untracked_in(tree: Map[String, String]) String:
	for name in sorted_keys(tree):
		if self.files.contains(name) and not self.index.contains(name): return name.clone()
	return ""

fn var Repo.switch_tree(tree: Map[String, String]) Void:
	for k in self.index.keys().clone():
		self.files.remove(k.clone())
	for e in tree.entries():
		self.files[e.key.clone()] = e.value.clone()
	self.index = tree.clone()

fn var Repo.reset_to(id: String) Void:
	old_head := self.tree_of(self.cur())
	for k in self.index.keys().clone():
		self.files.remove(k.clone())
	for k in old_head.keys().clone():
		self.files.remove(k.clone())
	tree := self.tree_of(id)
	for e in tree.entries():
		self.files[e.key.clone()] = e.value.clone()
	self.index = tree.clone()
	self.move_head(id)
	self.merging = false
	self.conflicts = Set[String]()

fn Repo.branch_label() String:
	if self.head_branch.length() > 0: return self.head_branch.clone()
	return "detached"

fn err(msg: String) Void:
	print("error: {msg}")

fn var Repo.create_branch(name: String) Bool:
	if not valid_name(name):
		err("invalid branch name '{name}'")
		return false
	if self.branches.contains(name):
		err("branch '{name}' already exists")
		return false
	c := self.cur()
	if c.length() == 0:
		err("no commits yet")
		return false
	self.branches[name.clone()] = c
	return true

fn var Repo.do_commit(msg: String) Void:
	if msg.length() == 0: return err("empty commit message")
	if self.conflicts.length() > 0:
		var names = List[String]()
		for c in self.conflicts.values(): names.append(c.clone())
		names.sort()
		return err("unresolved conflicts: {names.join(" ")}")
	cur := self.cur()
	if self.merging:
		id := self.make_commit(self.index.clone(), [cur.clone(), self.merge_other.clone()], msg)
		self.move_head(id)
		self.merging = false
		print("[{self.branch_label()} {short(id)}] {msg}")
		return
	if trees_equal(self.index, self.tree_of(cur)): return err("nothing to commit")
	var ps = List[String]()
	if cur.length() > 0: ps.append(cur.clone())
	id := self.make_commit(self.index.clone(), ps, msg)
	self.move_head(id)
	if cur.length() == 0:
		print("[{self.branch_label()} (root-commit) {short(id)}] {msg}")
	else:
		print("[{self.branch_label()} {short(id)}] {msg}")

fn var Repo.do_add(args: List[String]) Void:
	if args.length() == 0: return err("usage: add PATH...")
	for p in args:
		if p == ".":
			for e in self.files.entries():
				self.index[e.key.clone()] = e.value.clone()
			for k in self.index.keys().clone():
				if not self.files.contains(k): self.index.remove(k.clone())
			self.conflicts = Set[String]()
		else if w := self.files.get(p):
			self.index[p.clone()] = w.clone()
			self.conflicts.remove(p.clone())
		else if self.index.contains(p):
			self.index.remove(p.clone())
			self.conflicts.remove(p.clone())
		else if self.conflicts.contains(p):
			self.conflicts.remove(p.clone())
		else:
			return err("pathspec '{p}' did not match any files")

fn union_names(a: Map[String, String], b: Map[String, String]) List[String]:
	var s = Map[String, String]()
	for k in a.keys(): s[k.clone()] = ""
	for k in b.keys(): s[k.clone()] = ""
	return sorted_keys(s)

fn Repo.status() Void:
	if self.head_branch.length() > 0:
		print("On branch {self.head_branch}")
	else:
		print("HEAD detached at {short(self.head_commit)}")
	if self.merging: print("merging: {self.merge_branch}")
	headt := self.tree_of(self.cur())
	var staged = List[String]()
	var unstaged = List[String]()
	var confl = List[String]()
	var untr = List[String]()
	for name in union_names(headt, self.index):
		if self.conflicts.contains(name): continue
		h := headt.get(name)
		i := self.index.get(name)
		if i.is_some() and h.is_none(): staged.append("new file: {name}")
		else if i.is_none() and h.is_some(): staged.append("deleted: {name}")
		else if not same(h, i): staged.append("modified: {name}")
	for name in sorted_keys(self.index):
		if self.conflicts.contains(name): continue
		if w := self.files.get(name):
			if w != self.index.get_or(name, ""): unstaged.append("modified: {name}")
		else:
			unstaged.append("deleted: {name}")
	for c in self.conflicts.values(): confl.append("unmerged: {c}")
	confl.sort()
	for name in sorted_keys(self.files):
		if not self.index.contains(name) and not self.conflicts.contains(name): untr.append(name.clone())
	if staged.length() + unstaged.length() + confl.length() + untr.length() == 0:
		print("nothing to commit, working tree clean")
		return
	if staged.length() > 0:
		print("staged:")
		for s in staged: print("  {s}")
	if unstaged.length() > 0:
		print("unstaged:")
		for s in unstaged: print("  {s}")
	if confl.length() > 0:
		print("conflicts:")
		for s in confl: print("  {s}")
	if untr.length() > 0:
		print("untracked:")
		for s in untr: print("  {s}")

fn Repo.log(args: List[String]) Void:
	var limit = -1
	if args.length() == 2 and args.get(0, "") == "-n" and all_digits(args.get(1, "")):
		limit = args.get(1, "").parse_int().get(-1)
		if limit < 0: return err("usage: log [-n N]")
	else if args.length() != 0:
		return err("usage: log [-n N]")
	cur := self.cur()
	if cur.length() == 0: return print("no commits yet")
	anc := self.ancestors(cur)
	var shown = 0
	var i = self.order.length() - 1
	while i >= 0:
		if limit >= 0 and shown >= limit: break
		id := self.order.get(i, "")
		i -= 1
		if not anc.contains(id): continue
		ps := self.parents_of(id)
		if ps.length() == 2:
			print("{short(id)} {self.msg_of(id)} (merge {short(ps.get(0, ""))} {short(ps.get(1, ""))})")
		else:
			print("{short(id)} {self.msg_of(id)}")
		shown += 1

fn show_diff(left: Map[String, String], right: Map[String, String]) Void:
	var any = false
	for name in union_names(left, right):
		l := left.get(name)
		r := right.get(name)
		if same(l, r): continue
		any = true
		print("diff {name}")
		if l.is_none(): print("new file")
		if r.is_none(): print("deleted file")
		for x in line_diff(split_lines(left.get_or(name, "")), split_lines(right.get_or(name, ""))):
			print(x)
	if not any: print("(no differences)")

fn Repo.diff(args: List[String]) Void:
	if args.length() > 2: return err("usage: diff [REF [REF]]")
	if args.length() == 0:
		show_diff(self.index, self.files)
		return
	a := self.resolve(args.get(0, ""))
	if not a.is_ok(): return err(a.err().message)
	at := self.tree_of(a.get(""))
	if args.length() == 1:
		show_diff(at, self.files)
		return
	b := self.resolve(args.get(1, ""))
	if not b.is_ok(): return err(b.err().message)
	show_diff(at, self.tree_of(b.get("")))

fn var Repo.branch_cmd(args: List[String]) Void:
	if args.length() == 0:
		var names = self.branches.keys().clone()
		names.sort()
		if self.head_branch.length() == 0: print("* (HEAD detached at {short(self.head_commit)})")
		for n in names:
			if n == self.head_branch: print("* {n}")
			else: print("  {n}")
		return
	if args.length() == 2 and args.get(0, "") == "-d":
		name := args.get(1, "")
		if not self.branches.contains(name): return err("branch '{name}' not found")
		if name == self.head_branch: return err("cannot delete the current branch '{name}'")
		id := self.branches.get_or(name, "")
		cur := self.cur()
		if id.length() == 0 or not (id == cur or self.ancestors(cur).contains(id)):
			return err("branch '{name}' is not fully merged")
		self.branches.remove(name.clone())
		print("Deleted branch {name} (was {short(id)}).")
		return
	if args.length() == 1:
		_ := self.create_branch(args.get(0, ""))
		return
	err("usage: branch [NAME | -d NAME]")

fn var Repo.tag_cmd(args: List[String]) Void:
	if args.length() == 0:
		var names = self.tags.keys().clone()
		names.sort()
		for n in names: print(n)
		return
	if args.length() > 2: return err("usage: tag [NAME [REF]]")
	name := args.get(0, "")
	if not valid_name(name): return err("invalid tag name '{name}'")
	if self.tags.contains(name): return err("tag '{name}' already exists")
	var rv = "HEAD"
	if args.length() == 2: rv = args.get(1, "").clone()
	if rv == "HEAD" and self.cur().length() == 0: return err("no commits yet")
	r := self.resolve(rv)
	if not r.is_ok(): return err(r.err().message)
	self.tags[name.clone()] = r.get("")

fn Repo.show(args: List[String]) Void:
	if args.length() != 1: return err("usage: show REF")
	r := self.resolve(args.get(0, ""))
	if not r.is_ok(): return err(r.err().message)
	id := r.get("")
	tree := self.tree_of(id)
	print("commit {id}")
	print("tree {tree_hash(tree)}")
	for p in self.parents_of(id): print("parent {p}")
	print("message: {self.msg_of(id)}")
	print("files:")
	for n in sorted_keys(tree):
		print("  {n} {short(hash_of(tree.get_or(n, "")))}")

fn var Repo.checkout(args: List[String]) Void:
	if args.length() == 2 and args.get(0, "") == "-b":
		name := args.get(1, "")
		if self.create_branch(name):
			self.head_branch = name.clone()
			self.head_commit = ""
			print("Switched to a new branch '{name}'")
		return
	if args.length() != 1: return err("usage: checkout REF | checkout -b NAME")
	if self.merging: return err("merge in progress")
	target := args.get(0, "")
	bid := self.branches.get_or(target, "")
	if self.branches.contains(target) and bid.length() > 0:
		if target == self.head_branch:
			print("Already on '{target}'")
			return
		if self.dirty(): return err("local changes would be overwritten")
		tree := self.tree_of(bid)
		u := self.untracked_in(tree)
		if u.length() > 0: return err("untracked file would be overwritten: {u}")
		self.switch_tree(tree)
		self.head_branch = target.clone()
		self.head_commit = ""
		print("Switched to branch '{target}'")
		return
	r := self.resolve(target)
	if not r.is_ok(): return err(r.err().message)
	id := r.get("")
	if self.dirty(): return err("local changes would be overwritten")
	tree := self.tree_of(id)
	u := self.untracked_in(tree)
	if u.length() > 0: return err("untracked file would be overwritten: {u}")
	self.switch_tree(tree)
	self.head_branch = ""
	self.head_commit = id.clone()
	print("HEAD is now at {short(id)} {self.msg_of(id)}")

fn var Repo.reset(args: List[String]) Void:
	if args.length() < 1 or args.length() > 2 or args.get(0, "") != "--hard": return err("usage: reset --hard [REF]")
	var id = ""
	if args.length() == 1:
		id = self.cur()
		if id.length() == 0: return err("no commits yet")
	else:
		r := self.resolve(args.get(1, ""))
		if not r.is_ok(): return err(r.err().message)
		id = r.get("")
	self.reset_to(id)
	print("HEAD is now at {short(id)} {self.msg_of(id)}")

fn var Repo.merge(args: List[String]) Void:
	if args.length() == 1 and args.get(0, "") == "--abort":
		if not self.merging: return err("no merge in progress")
		self.reset_to(self.cur())
		print("Merge aborted.")
		return
	if args.length() != 1: return err("usage: merge BRANCH")
	branch := args.get(0, "")
	if self.merging: return err("merge in progress")
	cur := self.cur()
	if cur.length() == 0: return err("no commits yet")
	other := self.branches.get_or(branch, "")
	if other.length() == 0: return err("unknown branch '{branch}'")
	if self.dirty(): return err("local changes would be overwritten")
	cur_anc := self.ancestors(cur)
	if cur_anc.contains(other):
		print("Already up to date.")
		return
	other_anc := self.ancestors(other)
	if other_anc.contains(cur):
		tree := self.tree_of(other)
		u := self.untracked_in(tree)
		if u.length() > 0: return err("untracked file would be overwritten: {u}")
		self.switch_tree(tree)
		self.move_head(other)
		print("Fast-forward")
		return
	var base_id = ""
	var best = 0
	for c in cur_anc.values():
		if other_anc.contains(c) and self.num_of(c) > best:
			best = self.num_of(c)
			base_id = c.clone()
	b := self.tree_of(base_id)
	o := self.tree_of(cur)
	t := self.tree_of(other)
	var names = Map[String, String]()
	for k in b.keys(): names[k.clone()] = ""
	for k in o.keys(): names[k.clone()] = ""
	for k in t.keys(): names[k.clone()] = ""
	var res = Map[String, String]()
	var idx_extra = Map[String, String]()
	var over = Map[String, String]()
	var kinds = Map[String, String]()
	for name in sorted_keys(names):
		bv := b.get(name)
		ov := o.get(name)
		tv := t.get(name)
		if same(ov, tv):
			if x := ov: res[name.clone()] = x.clone()
		else if same(ov, bv):
			if x := tv: res[name.clone()] = x.clone()
		else if same(tv, bv):
			if x := ov: res[name.clone()] = x.clone()
		else:
			if ov.is_none() or tv.is_none():
				kinds[name.clone()] = "modify/delete"
				if x := ov:
					over[name.clone()] = x.clone()
					idx_extra[name.clone()] = x.clone()
				if x := tv:
					over[name.clone()] = x.clone()
			else:
				bl := split_lines(bv.get(""))
				m := merge3(bl, split_lines(ov.get("")), split_lines(tv.get("")), branch)
				if m.conflict:
					idx_extra[name.clone()] = ov.get("").clone()
					over[name.clone()] = join_lines(m.out)
					kinds[name.clone()] = if bv.is_some(): "content" else: "add/add"
				else:
					res[name.clone()] = join_lines(m.out)
	var check = res.clone()
	for e in over.entries(): check[e.key.clone()] = e.value.clone()
	u := self.untracked_in(check)
	if u.length() > 0: return err("untracked file would be overwritten: {u}")
	for k in self.index.keys().clone():
		if not res.contains(k): self.files.remove(k.clone())
	for e in res.entries(): self.files[e.key.clone()] = e.value.clone()
	for e in over.entries(): self.files[e.key.clone()] = e.value.clone()
	var newidx = res.clone()
	for e in idx_extra.entries(): newidx[e.key.clone()] = e.value.clone()
	self.index = newidx
	if kinds.length() == 0:
		msg := "Merge branch '{branch}'"
		id := self.make_commit(self.index.clone(), [cur.clone(), other.clone()], msg)
		self.move_head(id)
		print("Merge made by the 'three-way' strategy.")
		print("[{self.branch_label()} {short(id)}] {msg}")
		return
	self.merging = true
	self.merge_other = other.clone()
	self.merge_branch = branch.clone()
	self.conflicts = Set[String]()
	for k in sorted_keys(kinds):
		self.conflicts.add(k.clone())
		kind := kinds.get_or(k, "")
		if kind == "modify/delete": print("CONFLICT (modify/delete): {k}")
		else: print("CONFLICT ({kind}): Merge conflict in {k}")
	print("Automatic merge failed; fix conflicts and then commit the result.")

fn var Repo.run(line: String, block: List[String]) Void:
	t := line.trim()
	args := t.fields()
	cmd := args.get(0, "")
	var rest = List[String]()
	for i in 1..args.length(): rest.append(args.get(i, "").clone())
	if cmd == "write" or cmd == "append":
		if rest.length() != 1: return err("usage: {cmd} FILE")
		f := rest.get(0, "")
		if cmd == "write":
			self.files[f.clone()] = join_lines(block)
		else:
			self.files[f.clone()] = self.files.get_or(f, "") + join_lines(block)
	else if cmd == "rm":
		if rest.length() == 0: return err("usage: rm FILE...")
		for f in rest:
			if not self.files.contains(f): return err("no such file: {f}")
			self.files.remove(f)
	else if cmd == "mv":
		if rest.length() != 2: return err("usage: mv OLD NEW")
		a := rest.get(0, "")
		if not self.files.contains(a): return err("no such file: {a}")
		c := self.files.get_or(a, "").clone()
		self.files.remove(a)
		self.files[rest.get(1, "").clone()] = c
	else if cmd == "cat":
		if rest.length() != 1: return err("usage: cat FILE")
		f := rest.get(0, "")
		if c := self.files.get(f):
			for l in split_lines(c): print(l)
		else:
			err("no such file: {f}")
	else if cmd == "ls":
		if self.files.length() == 0: print("(empty)")
		for n in sorted_keys(self.files): print(n)
	else if cmd == "add": self.do_add(rest)
	else if cmd == "status": self.status()
	else if cmd == "commit":
		self.do_commit(t.slice(6, t.length()).get("").trim())
	else if cmd == "log": self.log(rest)
	else if cmd == "diff": self.diff(rest)
	else if cmd == "branch": self.branch_cmd(rest)
	else if cmd == "tag": self.tag_cmd(rest)
	else if cmd == "show": self.show(rest)
	else if cmd == "checkout": self.checkout(rest)
	else if cmd == "merge": self.merge(rest)
	else if cmd == "reset": self.reset(rest)
	else: err("unknown command '{cmd}'")

fn main() Void!:
	var all = List[String]()
	for line in lines(stdin()):
		all.append(line.clone())
	var repo = Repo()
	repo.branches["main"] = ""
	var i = 0
	while i < all.length():
		line := all.get(i, "").clone()
		i += 1
		t := line.trim()
		if t.length() == 0 or t.starts_with("#"): continue
		print("> {line.trim_end()}")
		args := t.fields()
		var block = List[String]()
		cmd := args.get(0, "")
		if (cmd == "write" or cmd == "append") and args.length() == 2:
			while i < all.length():
				l := all.get(i, "")
				i += 1
				if l == ".": break
				block.append(l.clone())
		repo.run(line, block)
