import fnv1a64 from "@std/crypto/hash.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type Commit:
	id: String
	parents: List[Int]
	msg: String
	tree: Map[String, String]

type Repo:
	commits: List[Commit] = []
	branches: Map[String, Int] = Map[String, Int]()
	tags: Map[String, Int] = Map[String, Int]()
	head_branch: String = "main"
	head_detached: Int = -1
	work: Map[String, String] = Map[String, String]()
	index: Map[String, String] = Map[String, String]()
	conflicts: Set[String] = Set[String]()
	merging: Bool = false
	merge_other: Int = -1
	merge_branch: String = ""

// ms: allow_effect std.console.write
fn out(s: String) Unit:
	print(s)

fn err(s: String) Unit:
	out("error: {s}")

fn hash_text(s: String) String:
	h := fnv1a64(s.to_bytes())
	return h.to_string_radix(16).pad_start(16, "0")

fn short(s: String) String:
	return s.view(0, 7).clone()

fn tree_hash(t: Map[String, String]) String:
	var text = ""
	names := t.keys().sorted()
	for n in names:
		text = text + n + " " + hash_text(t.get_or(n, "")) + "\n"
	return hash_text(text)

fn trees_equal(a: Map[String, String], b: Map[String, String]) Bool:
	if a.length() != b.length(): return false
	for n in a.keys():
		x := a.get(n)
		y := b.get(n)
		if y.is_none(): return false
		if x.get("") != y.get(""): return false
	return true

fn to_lines(content: String) List[String]:
	if content == "": return List[String]()
	var parts = content.split("\n").clone()
	parts.pop()
	return parts.clone()

fn from_lines(ls: List[String]) String:
	var s = ""
	for l in ls:
		s = s + l + "\n"
	return s

fn sub_list(xs: List[String], a: Int, b: Int) List[String]:
	var r = List[String]()
	var i = a
	while i < b:
		r.append(xs.get(i, "").clone())
		i += 1
	return r

// For each index of a, the matched index of b or -1.
fn matching(a: List[String], b: List[String]) List[Int]:
	n := a.length()
	m := b.length()
	w := m + 1
	var table = List[Int]()
	var k = 0
	while k < (n + 1) * w:
		table.append(0)
		k += 1
	var i = n - 1
	while i >= 0:
		var j = m - 1
		while j >= 0:
			if a.get(i, "") == b.get(j, ""):
				table.replace(i * w + j, 1 + table.get((i + 1) * w + j + 1, 0))
			else:
				x := table.get((i + 1) * w + j, 0)
				y := table.get(i * w + j + 1, 0)
				table.replace(i * w + j, if x >= y: x else: y)
			j -= 1
		i -= 1
	var res = List[Int]()
	for _q in 0..n:
		res.append(-1)
	var p = 0
	var q = 0
	while p < n and q < m:
		if a.get(p, "") == b.get(q, ""):
			res.replace(p, q)
			p += 1
			q += 1
		else if table.get((p + 1) * w + q, 0) >= table.get(p * w + q + 1, 0):
			p += 1
		else:
			q += 1
	return res

fn diff_lines(a: List[String], b: List[String]) List[String]:
	mt := matching(a, b)
	var res = List[String]()
	var ci = 0
	var cj = 0
	for p in 0..a.length():
		q := mt.get(p, -1)
		if q < 0: continue
		while ci < p:
			res.append("- " + a.get(ci, ""))
			ci += 1
		while cj < q:
			res.append("+ " + b.get(cj, ""))
			cj += 1
		res.append("  " + a.get(p, ""))
		ci = p + 1
		cj = q + 1
	while ci < a.length():
		res.append("- " + a.get(ci, ""))
		ci += 1
	while cj < b.length():
		res.append("+ " + b.get(cj, ""))
		cj += 1
	return res

fn resolve_chunk(res: List[String], bc: List[String], oc: List[String], tc: List[String], branch: String) List[String]:
	var r = res.clone()
	if oc == bc:
		r.extend(tc)
	else if tc == bc:
		r.extend(oc)
	else if oc == tc:
		r.extend(oc)
	else:
		r.append("<<<<<<< HEAD")
		r.extend(oc)
		r.append("=======")
		r.extend(tc)
		r.append(">>>>>>> " + branch)
	return r

// Returns merged text lines and whether there was a conflict.
fn merge3(base: List[String], ours: List[String], theirs: List[String], branch: String) Tuple2:
	mo := matching(base, ours)
	mt := matching(base, theirs)
	var res = List[String]()
	var conflict = false
	var pb = -1
	var po = -1
	var pt = -1
	for k in 0..(base.length() + 1):
		var o = ours.length()
		var t = theirs.length()
		if k < base.length():
			o = mo.get(k, -1)
			t = mt.get(k, -1)
			if o < 0 or t < 0: continue
		bc := sub_list(base, pb + 1, k)
		oc := sub_list(ours, po + 1, o)
		tc := sub_list(theirs, pt + 1, t)
		if oc != bc and tc != bc and oc != tc:
			conflict = true
		res = resolve_chunk(res, bc, oc, tc, branch)
		if k < base.length():
			res.append(base.get(k, "").clone())
		pb = k
		po = o
		pt = t
	return Tuple2(lines: res, conflict: conflict)

type Tuple2:
	lines: List[String]
	conflict: Bool

fn is_digits(s: String) Bool:
	if s == "": return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

fn is_hex_lower(s: String) Bool:
	for c in s.chars():
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")): return false
	return true

fn cur_commit(repo: Repo) Int:
	if repo.head_branch != "":
		return repo.branches.get_or(repo.head_branch, -1)
	return repo.head_detached

fn head_tree(repo: Repo) Map[String, String]:
	c := cur_commit(repo)
	if c < 0: return Map[String, String]()
	return repo.commits.get(c).tree.clone()

fn unknown(r: String) Error:
	return Error("unknown revision '{r}'")

fn resolve(repo: Repo, r: String) Int!:
	var base = r.clone()
	var steps = 0
	if idx := r.index_of("~"):
		base = r.view(0, idx).clone()
		rest := r.view(idx + 1, r.length())
		if not is_digits(rest): return error(unknown(r))
		if n := rest.parse_int():
			steps = n
		else:
			return error(unknown(r))
	var found = -1
	if base == "HEAD":
		found = cur_commit(repo)
		if found < 0: return error(unknown(r))
	else:
		b := repo.branches.get_or(base, -1)
		if b >= 0:
			found = b
		else if repo.tags.contains(base):
			found = repo.tags.get_or(base, -1)
		else if base.length() >= 4 and base.length() <= 16 and is_hex_lower(base):
			var count = 0
			for i in 0..repo.commits.length():
				if repo.commits.get(i).id.starts_with(base):
					count += 1
					found = i
			if count > 1: return error(Error("ambiguous revision '{r}'"))
	if found < 0: return error(unknown(r))
	var k = 0
	while k < steps:
		ps := repo.commits.get(found).parents.clone()
		if ps.length() == 0: return error(unknown(r))
		found = ps.get(0, -1)
		k += 1
	return ok(found)

fn ancestors(repo: Repo, c: Int) Set[Int]:
	var seen = Set[Int]()
	var stack = [c]
	while stack.length() > 0:
		x := stack.pop().get(-1)
		if x < 0 or seen.contains(x): continue
		seen.add(x)
		for p in repo.commits.get(x).parents.clone():
			stack.append(p)
	return seen

fn short_of(repo: Repo, c: Int) String:
	return short(repo.commits.get(c).id)

fn make_commit(var repo: Repo, tree: Map[String, String], parents: List[Int], msg: String) Int:
	var text = "tree " + tree_hash(tree) + "\n"
	for p in parents:
		text = text + "parent " + repo.commits.get(p).id + "\n"
	text = text + "\n" + msg + "\n"
	id := hash_text(text)
	for i in 0..repo.commits.length():
		if repo.commits.get(i).id == id: return i
	repo.commits.append(Commit(id: id, parents: parents.clone(), msg: msg.clone(), tree: tree.clone()))
	return repo.commits.length() - 1

fn move_head(var repo: Repo, c: Int) Unit:
	if repo.head_branch != "":
		repo.branches.add(repo.head_branch.clone(), c)
	else:
		repo.head_detached = c

fn head_label(repo: Repo) String:
	if repo.head_branch != "": return repo.head_branch.clone()
	return "detached"

fn is_dirty(repo: Repo) Bool:
	if not trees_equal(repo.index, head_tree(repo)): return true
	for n in repo.index.keys():
		w := repo.work.get(n)
		if w.is_none(): return true
		if w.get("") != repo.index.get_or(n, ""): return true
	return false

fn untracked_name(repo: Repo, names: List[String]) String?:
	for n in names.sorted():
		if not repo.index.contains(n) and repo.work.contains(n): return n.clone()
	return none

fn apply_tree(var repo: Repo, tree: Map[String, String]) Unit:
	for n in repo.index.keys():
		repo.work.remove(n.clone())
	for n in tree.keys():
		repo.work.add(n.clone(), tree.get_or(n, ""))
	repo.index = tree.clone()

fn valid_name(s: String) Bool:
	if s == "": return false
	var first = true
	for c in s.chars():
		ok_c := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "." or c == "_" or c == "/"
		if first:
			if not ok_c: return false
		else:
			if not ok_c and c != "-": return false
		first = false
	return true

fn content_of(t: Map[String, String], n: String) String?:
	return t.get(n)

fn do_commit_msg(var repo: Repo, msg: String) Unit:
	if msg == "":
		err("empty commit message")
		return
	if repo.conflicts.length() > 0:
		out("error: unresolved conflicts: " + repo.conflicts.values().sorted().join(" "))
		return
	if repo.merging:
		c := cur_commit(repo)
		id := make_commit(var repo, repo.index.clone(), [c, repo.merge_other], msg)
		move_head(var repo, id)
		repo.merging = false
		repo.merge_other = -1
		out("[{head_label(repo)} {short_of(repo, id)}] {msg}")
		return
	if trees_equal(repo.index, head_tree(repo)):
		err("nothing to commit")
		return
	c := cur_commit(repo)
	var ps = List[Int]()
	if c >= 0: ps.append(c)
	id := make_commit(var repo, repo.index.clone(), ps, msg)
	move_head(var repo, id)
	if c < 0:
		out("[{head_label(repo)} (root-commit) {short_of(repo, id)}] {msg}")
	else:
		out("[{head_label(repo)} {short_of(repo, id)}] {msg}")

fn do_log(repo: Repo, args: List[String]) Unit:
	var limit = -1
	if args.length() == 2 and args.get(0, "") == "-n" and is_digits(args.get(1, "")):
		if n := args.get(1, "").parse_int():
			limit = n
		else:
			out("error: usage: log [-n N]")
			return
	else if args.length() != 0:
		out("error: usage: log [-n N]")
		return
	c := cur_commit(repo)
	if c < 0:
		out("no commits yet")
		return
	var ids = ancestors(repo, c).values().sorted()
	ids.reverse()
	var count = 0
	for id in ids:
		if limit >= 0 and count >= limit: break
		cm := repo.commits.get(id)
		if cm.parents.length() == 2:
			out("{short(cm.id)} {cm.msg} (merge {short_of(repo, cm.parents.get(0, 0))} {short_of(repo, cm.parents.get(1, 0))})")
		else:
			out("{short(cm.id)} {cm.msg}")
		count += 1

fn print_diff(a: Map[String, String], b: Map[String, String]) Unit:
	var names = a.keys().clone()
	for n in b.keys():
		if not a.contains(n): names.append(n.clone())
	var any = false
	for n in names.sorted():
		x := a.get(n)
		y := b.get(n)
		if x.get("") == y.get("") and x.is_some() == y.is_some(): continue
		any = true
		out("diff {n}")
		if x.is_none(): out("new file")
		if y.is_none(): out("deleted file")
		for l in diff_lines(to_lines(x.get("")), to_lines(y.get(""))):
			out(l)
	if not any: out("(no differences)")

fn do_diff(repo: Repo, args: List[String]) Unit:
	if args.length() > 2:
		err("usage: diff [REF [REF]]")
		return
	if args.length() == 0:
		print_diff(repo.index, repo.work)
		return
	r1 := resolve(repo, args.get(0, ""))
	if c1 := r1:
		if args.length() == 1:
			print_diff(repo.commits.get(c1).tree, repo.work)
			return
		r2 := resolve(repo, args.get(1, ""))
		if c2 := r2:
			print_diff(repo.commits.get(c1).tree, repo.commits.get(c2).tree)
		else:
			err(r2.err().message)
	else:
		err(r1.err().message)

fn do_branch(var repo: Repo, args: List[String]) Unit:
	if args.length() == 0:
		var names = repo.branches.keys().sorted()
		if repo.head_branch == "":
			out("* (HEAD detached at {short_of(repo, repo.head_detached)})")
		for n in names:
			if n == repo.head_branch:
				out("* {n}")
			else:
				out("  {n}")
		return
	if args.length() == 2 and args.get(0, "") == "-d":
		name := args.get(1, "")
		b := repo.branches.get_or(name, -2)
		if b == -2:
			err("branch '{name}' not found")
			return
		if name == repo.head_branch:
			err("cannot delete the current branch '{name}'")
			return
		c := cur_commit(repo)
		if c < 0 or b < 0 or not ancestors(repo, c).contains(b):
			err("branch '{name}' is not fully merged")
			return
		repo.branches.remove(name.clone())
		out("Deleted branch {name} (was {short_of(repo, b)}).")
		return
	if args.length() != 1:
		err("usage: branch [NAME | -d NAME]")
		return
	if not create_branch(var repo, args.get(0, "")): return

fn create_branch(var repo: Repo, name: String) Bool:
	if not valid_name(name):
		err("invalid branch name '{name}'")
		return false
	if repo.branches.contains(name):
		err("branch '{name}' already exists")
		return false
	c := cur_commit(repo)
	if c < 0:
		err("no commits yet")
		return false
	repo.branches.add(name.clone(), c)
	return true

fn do_tag(var repo: Repo, args: List[String]) Unit:
	if args.length() > 2:
		err("usage: tag [NAME [REF]]")
		return
	if args.length() == 0:
		for n in repo.tags.keys().sorted():
			out(n)
		return
	name := args.get(0, "")
	if not valid_name(name):
		err("invalid tag name '{name}'")
		return
	if repo.tags.contains(name):
		err("tag '{name}' already exists")
		return
	if args.length() == 1 or args.get(1, "") == "HEAD":
		if cur_commit(repo) < 0:
			err("no commits yet")
			return
	var r = "HEAD"
	if args.length() == 2: r = args.get(1, "")
	res := resolve(repo, r)
	if c := res:
		repo.tags.add(name.clone(), c)
	else:
		err(res.err().message)

fn do_show(repo: Repo, args: List[String]) Unit:
	if args.length() != 1:
		err("usage: show REF")
		return
	res := resolve(repo, args.get(0, ""))
	if c := res:
		cm := repo.commits.get(c)
		out("commit {cm.id}")
		out("tree {tree_hash(cm.tree)}")
		for p in cm.parents:
			out("parent {repo.commits.get(p).id}")
		out("message: {cm.msg}")
		out("files:")
		for n in cm.tree.keys().sorted():
			out("  {n} {short(hash_text(cm.tree.get_or(n, "")))}")
	else:
		err(res.err().message)

fn switch_checks(repo: Repo, target: Map[String, String]) String?:
	if is_dirty(repo): return "local changes would be overwritten"
	if n := untracked_name(repo, target.keys()):
		return "untracked file would be overwritten: {n}"
	return none

fn do_checkout(var repo: Repo, args: List[String]) Unit:
	if args.length() == 2 and args.get(0, "") == "-b":
		name := args.get(1, "")
		if not create_branch(var repo, name): return
		repo.head_branch = name.clone()
		out("Switched to a new branch '{name}'")
		return
	if args.length() != 1:
		err("usage: checkout REF | checkout -b NAME")
		return
	if repo.merging:
		err("merge in progress")
		return
	t := args.get(0, "")
	if repo.branches.contains(t):
		if t == repo.head_branch:
			out("Already on '{t}'")
			return
		c := repo.branches.get_or(t, -1)
		tree := repo.commits.get(c).tree.clone()
		if msg := switch_checks(repo, tree):
			err(msg)
			return
		apply_tree(var repo, tree)
		repo.head_branch = t.clone()
		out("Switched to branch '{t}'")
		return
	res := resolve(repo, t)
	if c := res:
		tree := repo.commits.get(c).tree.clone()
		if msg := switch_checks(repo, tree):
			err(msg)
			return
		apply_tree(var repo, tree)
		repo.head_branch = ""
		repo.head_detached = c
		out("HEAD is now at {short_of(repo, c)} {repo.commits.get(c).msg}")
	else:
		err(res.err().message)

fn hard_reset(var repo: Repo, c: Int) Unit:
	for n in repo.index.keys():
		repo.work.remove(n.clone())
	for n in head_tree(repo).keys():
		repo.work.remove(n.clone())
	move_head(var repo, c)
	tree := repo.commits.get(c).tree.clone()
	for n in tree.keys():
		repo.work.add(n.clone(), tree.get_or(n, ""))
	repo.index = tree
	repo.merging = false
	repo.merge_other = -1
	repo.conflicts = Set[String]()

fn do_reset(var repo: Repo, args: List[String]) Unit:
	if args.length() < 1 or args.length() > 2 or args.get(0, "") != "--hard":
		err("usage: reset --hard [REF]")
		return
	var c = -1
	if args.length() == 1:
		c = cur_commit(repo)
		if c < 0:
			err("no commits yet")
			return
	else:
		res := resolve(repo, args.get(1, ""))
		if x := res:
			c = x
		else:
			err(res.err().message)
			return
	hard_reset(var repo, c)
	out("HEAD is now at {short_of(repo, c)} {repo.commits.get(c).msg}")

fn do_merge(var repo: Repo, args: List[String]) Unit:
	if args.length() == 1 and args.get(0, "") == "--abort":
		if not repo.merging:
			err("no merge in progress")
			return
		hard_reset(var repo, cur_commit(repo))
		out("Merge aborted.")
		return
	if args.length() != 1:
		err("usage: merge BRANCH")
		return
	if repo.merging:
		err("merge in progress")
		return
	cur := cur_commit(repo)
	if cur < 0:
		err("no commits yet")
		return
	branch := args.get(0, "")
	other := repo.branches.get_or(branch, -1)
	if other < 0:
		err("unknown branch '{branch}'")
		return
	if is_dirty(repo):
		err("local changes would be overwritten")
		return
	cur_anc := ancestors(repo, cur)
	if cur_anc.contains(other):
		out("Already up to date.")
		return
	other_anc := ancestors(repo, other)
	if other_anc.contains(cur):
		tree := repo.commits.get(other).tree.clone()
		if n := untracked_name(repo, tree.keys()):
			err("untracked file would be overwritten: {n}")
			return
		apply_tree(var repo, tree)
		move_head(var repo, other)
		out("Fast-forward")
		return
	var base_id = -1
	for x in cur_anc.values():
		if other_anc.contains(x) and x > base_id: base_id = x
	var bt = Map[String, String]()
	if base_id >= 0: bt = repo.commits.get(base_id).tree.clone()
	ot := repo.commits.get(cur).tree.clone()
	tt := repo.commits.get(other).tree.clone()
	var names = Set[String]()
	for n in bt.keys(): names.add(n.clone())
	for n in ot.keys(): names.add(n.clone())
	for n in tt.keys(): names.add(n.clone())
	var result = Map[String, String]()
	var new_index = Map[String, String]()
	var overrides = Map[String, String]()
	var conflict_names = List[String]()
	var conflict_kind = Map[String, String]()
	for n in names.values().sorted():
		b := bt.get(n)
		o := ot.get(n)
		t := tt.get(n)
		same_ot := o.is_some() == t.is_some() and o.get("") == t.get("")
		o_eq_b := o.is_some() == b.is_some() and o.get("") == b.get("")
		t_eq_b := t.is_some() == b.is_some() and t.get("") == b.get("")
		if same_ot or t_eq_b:
			if o.is_some(): result.add(n.clone(), o.get(""))
		else if o_eq_b:
			if t.is_some(): result.add(n.clone(), t.get(""))
		else if o.is_none() or t.is_none():
			conflict_names.append(n.clone())
			conflict_kind.add(n.clone(), "modify/delete")
			if o.is_some():
				new_index.add(n.clone(), o.get(""))
				overrides.add(n.clone(), o.get(""))
			else:
				overrides.add(n.clone(), t.get(""))
		else:
			m := merge3(to_lines(b.get("")), to_lines(o.get("")), to_lines(t.get("")), branch)
			if m.conflict:
				conflict_names.append(n.clone())
				conflict_kind.add(n.clone(), if b.is_some(): "content" else: "add/add")
				new_index.add(n.clone(), o.get(""))
				overrides.add(n.clone(), from_lines(m.lines))
			else:
				result.add(n.clone(), from_lines(m.lines))
	var check_names = result.keys().clone()
	for n in new_index.keys(): check_names.append(n.clone())
	for n in overrides.keys(): check_names.append(n.clone())
	if n := untracked_name(repo, check_names):
		err("untracked file would be overwritten: {n}")
		return
	var full_index = result.clone()
	for n in new_index.keys(): full_index.add(n.clone(), new_index.get_or(n, ""))
	for n in repo.index.keys():
		if not full_index.contains(n) and not overrides.contains(n):
			repo.work.remove(n.clone())
	for n in full_index.keys():
		repo.work.add(n.clone(), full_index.get_or(n, ""))
	for n in overrides.keys():
		repo.work.add(n.clone(), overrides.get_or(n, ""))
	repo.index = full_index
	if conflict_names.length() == 0:
		id := make_commit(var repo, result, [cur, other], "Merge branch '{branch}'")
		move_head(var repo, id)
		out("Merge made by the 'three-way' strategy.")
		out("[{head_label(repo)} {short_of(repo, id)}] Merge branch '{branch}'")
		return
	repo.merging = true
	repo.merge_other = other
	repo.merge_branch = branch.clone()
	for n in conflict_names:
		repo.conflicts.add(n.clone())
		kind := conflict_kind.get_or(n, "")
		if kind == "modify/delete":
			out("CONFLICT (modify/delete): {n}")
		else:
			out("CONFLICT ({kind}): Merge conflict in {n}")
	out("Automatic merge failed; fix conflicts and then commit the result.")

fn do_add(var repo: Repo, args: List[String]) Unit:
	if args.length() == 0:
		err("usage: add PATH...")
		return
	for p in args:
		if p == ".":
			for n in repo.work.keys():
				repo.index.add(n.clone(), repo.work.get_or(n, ""))
				repo.conflicts.remove(n.clone())
			for n in repo.index.keys().clone():
				if not repo.work.contains(n):
					repo.index.remove(n.clone())
					repo.conflicts.remove(n.clone())
		else if repo.work.contains(p):
			repo.index.add(p.clone(), repo.work.get_or(p, ""))
			repo.conflicts.remove(p.clone())
		else if repo.index.contains(p):
			repo.index.remove(p.clone())
			repo.conflicts.remove(p.clone())
		else if repo.conflicts.contains(p):
			repo.conflicts.remove(p.clone())
		else:
			err("pathspec '{p}' did not match any files")
			return

fn do_status(repo: Repo) Unit:
	if repo.head_branch != "":
		out("On branch {repo.head_branch}")
	else:
		out("HEAD detached at {short_of(repo, repo.head_detached)}")
	if repo.merging: out("merging: {repo.merge_branch}")
	ht := head_tree(repo)
	var staged = List[String]()
	var names = ht.keys().clone()
	for n in repo.index.keys():
		if not ht.contains(n): names.append(n.clone())
	for n in names.sorted():
		if repo.conflicts.contains(n): continue
		h := ht.get(n)
		i := repo.index.get(n)
		if h.is_none():
			staged.append("new file: {n}")
		else if i.is_none():
			staged.append("deleted: {n}")
		else if h.get("") != i.get(""):
			staged.append("modified: {n}")
	var unstaged = List[String]()
	for n in repo.index.keys().sorted():
		if repo.conflicts.contains(n): continue
		w := repo.work.get(n)
		if w.is_none():
			unstaged.append("deleted: {n}")
		else if w.get("") != repo.index.get_or(n, ""):
			unstaged.append("modified: {n}")
	var conf = List[String]()
	for n in repo.conflicts.values().sorted():
		conf.append("unmerged: {n}")
	var untracked = List[String]()
	for n in repo.work.keys().sorted():
		if not repo.index.contains(n) and not repo.conflicts.contains(n):
			untracked.append(n.clone())
	if staged.length() + unstaged.length() + conf.length() + untracked.length() == 0:
		out("nothing to commit, working tree clean")
		return
	section("staged:", staged)
	section("unstaged:", unstaged)
	section("conflicts:", conf)
	section("untracked:", untracked)

fn section(title: String, items: List[String]) Unit:
	if items.length() == 0: return
	out(title)
	for i in items:
		out("  " + i)

fn rest_after_word(line: String) String:
	t := line.trim()
	idx := t.index_any(" \t").get(-1)
	if idx < 0: return ""
	return t.view(idx, t.length()).trim().clone()

fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().get("")
	var lines = text.split("\n").clone()
	if lines.length() > 0 and lines.get(lines.length() - 1, "") == "":
		lines.pop()
	var repo = Repo()
	repo.branches.add("main", -1)
	var i = 0
	while i < lines.length():
		line := lines.get(i, "").clone()
		i += 1
		t := line.trim()
		if t == "" or t.starts_with("#"): continue
		out("> " + line.trim_end())
		words := t.fields()
		cmd := words.get(0, "")
		args := words.drop(1)
		if cmd == "write" or cmd == "append":
			if args.length() != 1:
				err("usage: {cmd} FILE")
				continue
			var block = List[String]()
			while i < lines.length() and lines.get(i, "") != ".":
				block.append(lines.get(i, "").clone())
				i += 1
			i += 1
			name := args.get(0, "")
			var content = from_lines(block)
			if cmd == "append":
				content = repo.work.get_or(name, "") + content
			repo.work.add(name.clone(), content)
		else if cmd == "rm":
			if args.length() == 0:
				err("usage: rm FILE...")
				continue
			for n in args:
				if not repo.work.contains(n):
					err("no such file: {n}")
					break
				repo.work.remove(n.clone())
		else if cmd == "mv":
			if args.length() != 2:
				err("usage: mv OLD NEW")
				continue
			o := args.get(0, "")
			n := args.get(1, "")
			if not repo.work.contains(o):
				err("no such file: {o}")
				continue
			c := repo.work.get_or(o, "")
			repo.work.remove(o.clone())
			repo.work.add(n.clone(), c)
		else if cmd == "cat":
			if args.length() != 1:
				err("usage: cat FILE")
				continue
			n := args.get(0, "")
			if repo.work.contains(n):
				for l in to_lines(repo.work.get_or(n, "")):
					out(l)
			else:
				err("no such file: {n}")
		else if cmd == "ls":
			if repo.work.length() == 0:
				out("(empty)")
			else:
				for n in repo.work.keys().sorted():
					out(n)
		else if cmd == "add":
			do_add(var repo, args)
		else if cmd == "status":
			do_status(repo)
		else if cmd == "commit":
			do_commit_msg(var repo, rest_after_word(t))
		else if cmd == "log":
			do_log(repo, args)
		else if cmd == "diff":
			do_diff(repo, args)
		else if cmd == "branch":
			do_branch(var repo, args)
		else if cmd == "tag":
			do_tag(var repo, args)
		else if cmd == "show":
			do_show(repo, args)
		else if cmd == "checkout":
			do_checkout(var repo, args)
		else if cmd == "merge":
			do_merge(var repo, args)
		else if cmd == "reset":
			do_reset(var repo, args)
		else:
			err("unknown command '{cmd}'")
