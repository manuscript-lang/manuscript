// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import (
    bit_xor,
    bit_and,
    shift_right_unsigned,
    wrapping_multiply
) from "@std/math/math.ms"

type Commit:
    id: String
    parents: List[String]
    tree: Map[String, String]
    message: String

type Ent:
    has: Bool
    text: String

type Pairs:
    ia: List[Int]
    ib: List[Int]

type Merged:
    text: String
    conflict: Bool

type Repo:
    wt: Map[String, String]
    idx: Map[String, String]
    commits: List[Commit]
    branches: Map[String, String]
    tags: Map[String, String]
    on_branch: Bool
    branch: String
    detached: String
    merging: Bool
    merge_other: String
    merge_branch: String
    conflicts: Map[String, String]

// ---------- hashing ----------

fn hex16(h: Int) String:
    var out = ""

    for i in 0..16:
        let d = bit_and(shift_right_unsigned(h, (15 - i) * 4), 15)
        out += "0123456789abcdef".view(d, d + 1)

    return out

fn fnv_hex(text: String) String:
    var h = -3750763034362895579
    let bs = text.as_bytes()

    for i in 0..bs.length():
        h = bit_xor(h, bs.get(i).to_int())
        h = wrapping_multiply(h, 1099511628211)

    return hex16(h)

fn short_id(id: String) String:
    return id.slice(0, 7).get("")

fn tree_hash(tree: Map[String, String]) String:
    var text = ""
    for n in sorted_keys(tree):
        text += n + " " + fnv_hex(tree[n]) + "\n"
    return fnv_hex(text)

fn commit_hash(tree_h: String, parents: List[String], message: String) String:
    var text = "tree " + tree_h + "\n"
    for p in parents:
        text += "parent " + p + "\n"
    text += "\n" + message + "\n"
    return fnv_hex(text)

// ---------- small helpers ----------

fn sorted_keys(m: Map[String, String]) List[String]:
    var names = m.keys()
    names.sort()
    return names

fn sorted_set(s: Set[String]) List[String]:
    var names = List[String]()
    for k in s:
        names.append(k.clone())
    names.sort()
    return names

fn same_tree(a: Map[String, String], b: Map[String, String]) Bool:
    if a.length() != b.length():
        return false

    for n in a.keys():
        if not b.contains(n):
            return false
        if a[n] != b[n]:
            return false

    return true

fn is_blank(c: String) Bool:
    return c == " " or c == "\t" or c == "\r"

fn rtrim(s: String) String:
    var e = s.length()
    while e > 0 and is_blank(s.view(e - 1, e)):
        e -= 1
    return s.slice(0, e).get("")

fn split_words(s: String) List[String]:
    var out = List[String]()
    for w in s.replace("\t", " ").split(" "):
        if w != "":
            out.append(w.clone())
    return out

fn all_digits(s: String) Bool:
    if s.length() == 0:
        return false

    for i in 0..s.length():
        let c = s.view(i, i + 1)
        if not (c >= "0" and c <= "9"):
            return false

    return true

fn is_hex_prefix(s: String) Bool:
    if s.length() < 4:
        return false

    for i in 0..s.length():
        let c = s.view(i, i + 1)
        let ok = (c >= "0" and c <= "9") or (c >= "a" and c <= "f")
        if not ok:
            return false

    return true

fn valid_name(s: String) Bool:
    if s == "":
        return false

    for i in 0..s.length():
        let c = s.view(i, i + 1)
        let ok = (
            (c >= "a" and c <= "z")
            or (c >= "A" and c <= "Z")
            or (c >= "0" and c <= "9")
            or c == "."
            or c == "_"
            or c == "/"
        )

        if i == 0:
            if not ok:
                return false
        else:
            if not (ok or c == "-"):
                return false

    return true

// Splits file content (lines each ending in "\n") into lines.
fn lines_of(content: String) List[String]:
    var out = List[String]()
    let parts = content.split("\n")
    for k in 0..(parts.length() - 1):
        out.append(parts[k].clone())
    return out

fn join_lines(lines: List[String]) String:
    var out = ""
    for l in lines:
        out += l + "\n"
    return out

fn sub_lines(xs: List[String], a: Int, b: Int) List[String]:
    var out = List[String]()
    for k in a..b:
        out.append(xs[k].clone())
    return out

fn lines_eq(x: List[String], y: List[String]) Bool:
    if x.length() != y.length():
        return false

    for k in 0..x.length():
        if x[k] != y[k]:
            return false
    return true

fn message_of(commits: List[Commit], id: String) String:
    let p = find_commit(commits, id)
    if p < 0:
        return ""

    return commits[p].message.clone()

fn tree_of(commits: List[Commit], id: String) Map[String, String]:
    let p = find_commit(commits, id)
    if p < 0:
        return Map[String, String]()

    return commits[p].tree.clone()

fn find_commit(commits: List[Commit], id: String) Int:
    for i in 0..commits.length():
        if commits[i].id == id:
            return i
    return -1

// The commit itself and all of its ancestors.
fn ancestors(commits: List[Commit], start: String) Set[String]:
    var seen = Set[String]()
    var stack = List[String]()
    stack.append(start.clone())

    var k = 0

    while k < stack.length():
        let cur = stack[k].clone()
        k += 1
        if seen.contains(cur):
            continue

        seen.add(cur.clone())

        let p = find_commit(commits, cur)
        if p >= 0:
            for par in commits[p].parents:
                stack.append(par.clone())

    return seen

fn merge_base(commits: List[Commit], a: String, b: String) String:
    let sa = ancestors(commits, a)
    let sb = ancestors(commits, b)
    var best = -1

    for id in sa:
        if sb.contains(id):
            let p = find_commit(commits, id)
            if p > best:
                best = p

    if best < 0:
        return ""

    return commits[best].id.clone()

// ---------- line diff ----------

fn match_pairs(a: List[String], b: List[String]) Pairs:
    let na = a.length()
    let nb = b.length()
    let w = nb + 1
    var lcs = List[Int]()
    for k in 0..((na + 1) * w):
        lcs.append(0)

    var i = na - 1

    while i >= 0:
        var j = nb - 1

        while j >= 0:
            if a[i] == b[j]:
                lcs[i * w + j] = 1 + lcs[(i + 1) * w + j + 1]
            else:
                let down = lcs[(i + 1) * w + j]
                let right = lcs[i * w + j + 1]

                if down >= right:
                    lcs[i * w + j] = down
                else:
                    lcs[i * w + j] = right

            j -= 1

        i -= 1

    var ia = List[Int]()
    var ib = List[Int]()
    var x = 0
    var y = 0

    while x < na and y < nb:
        if a[x] == b[y]:
            ia.append(x)
            ib.append(y)
            x += 1
            y += 1
        else if lcs[(x + 1) * w + y] >= lcs[x * w + y + 1]:
            x += 1
        else:
            y += 1

    return Pairs(ia: ia, ib: ib)

fn print_line_diff(a: List[String], b: List[String]) Unit:
    let p = match_pairs(a, b)
    var x = 0
    var y = 0

    for k in 0..p.ia.length():
        let pa = p.ia[k]
        let pb = p.ib[k]

        while x < pa:
            print("- " + a[x])
            x += 1

        while y < pb:
            print("+ " + b[y])
            y += 1

        print("  " + a[pa])
        x = pa + 1
        y = pb + 1

    while x < a.length():
        print("- " + a[x])
        x += 1

    while y < b.length():
        print("+ " + b[y])
        y += 1

// ---------- three-way merge ----------

// Appends the resolved chunk to out; returns true when it is a conflict.
fn emit_chunk(
    var out: List[String], base: List[String], ours: List[String], theirs: List[String],
    branch: String
) Bool:
    if lines_eq(ours, base):
        for l in theirs:
            out.append(l.clone())
        return false

    if lines_eq(theirs, base):
        for l in ours:
            out.append(l.clone())
        return false

    if lines_eq(ours, theirs):
        for l in ours:
            out.append(l.clone())
        return false

    out.append("<<<<<<< HEAD")
    for l in ours:
        out.append(l.clone())
    out.append("=======")
    for l in theirs:
        out.append(l.clone())
    out.append(">>>>>>> " + branch)
    return true

fn three_way(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Merged:
    let mo = match_pairs(base, ours)
    let mt = match_pairs(base, theirs)
    let nb = base.length()
    var op = List[Int]()
    var tp = List[Int]()

    for k in 0..nb:
        op.append(-1)
        tp.append(-1)

    for k in 0..mo.ia.length():
        op[mo.ia[k]] = mo.ib[k]
    for k in 0..mt.ia.length():
        tp[mt.ia[k]] = mt.ib[k]

    var out = List[String]()
    var conflict = false
    var pb = -1
    var pox = -1
    var ptx = -1

    for s in 0..nb:
        if op[s] >= 0 and tp[s] >= 0:
            let c = emit_chunk(
                var out, sub_lines(base, pb + 1, s), sub_lines(ours, pox + 1, op[s]),
                sub_lines(theirs, ptx + 1, tp[s]), branch
            )
            if c:
                conflict = true
            out.append(base[s].clone())
            pb = s
            pox = op[s]
            ptx = tp[s]

    let c = emit_chunk(
        var out, sub_lines(base, pb + 1, nb), sub_lines(ours, pox + 1, ours.length()),
        sub_lines(theirs, ptx + 1, theirs.length()), branch
    )
    if c:
        conflict = true
    return Merged(text: join_lines(out), conflict: conflict)

fn ent(m: Map[String, String], n: String) Ent:
    if m.contains(n):
        return Ent(has: true, text: m[n].clone())

    return Ent(has: false, text: "")

fn ent_eq(a: Ent, b: Ent) Bool:
    return a.has == b.has and a.text == b.text

// ---------- repository ----------

impl Repo:
    fn err(msg: String) Unit:
        print("error: " + msg)

    fn label() String:
        if self.on_branch:
            return self.branch.clone()

        return "detached"

    fn head_id() String:
        if self.on_branch:
            return self.branches.get(self.branch).get("")

        return self.detached.clone()

    fn head_tree() Map[String, String]:
        return tree_of(self.commits, self.head_id())

    var fn set_head(id: String) Unit:
        if self.on_branch:
            let b = self.branch.clone()
            self.branches[b] = id
        else:
            self.detached = id

    var fn make_commit(
        tree: Map[String, String],
        parents: List[String],
        message: String
    ) String:
        let id = commit_hash(tree_hash(tree), parents, message)
        if find_commit(self.commits, id) < 0:
            self.commits.append(
                Commit(
                    id: id.clone(), parents: parents, tree: tree, message: message
                )
            )
        return id

    fn resolve(refname: String) String:
        let parts = refname.split("~")

        if parts.length() > 2:
            self.err("unknown revision '" + refname + "'")
            return ""

        var steps = 0

        if parts.length() == 2:
            let ns = parts[1].clone()

            if not all_digits(ns):
                self.err("unknown revision '" + refname + "'")
                return ""

            steps = ns.parse_int().get(-1)

            if steps < 0:
                self.err("unknown revision '" + refname + "'")
                return ""

        let base = parts[0].clone()
        var id = ""

        if base == "HEAD":
            id = self.head_id()
        else if self.branches.contains(base) and self.branches[base] != "":
            id = self.branches[base].clone()
        else if self.tags.contains(base):
            id = self.tags[base].clone()
        else if is_hex_prefix(base):
            var found = 0
            var hit = ""

            for c in self.commits:
                if c.id.starts_with(base):
                    found += 1
                    hit = c.id.clone()

            if found > 1:
                self.err("ambiguous revision '" + refname + "'")
                return ""

            if found == 1:
                id = hit

        if id == "":
            self.err("unknown revision '" + refname + "'")
            return ""

        for k in 0..steps:
            let p = find_commit(self.commits, id)

            if self.commits[p].parents.length() == 0:
                self.err("unknown revision '" + refname + "'")
                return ""

            id = self.commits[p].parents[0].clone()

        return id

    fn dirty() Bool:
        if not same_tree(self.idx, self.head_tree()):
            return true

        for n in self.idx.keys():
            if not self.wt.contains(n):
                return true
            if self.wt[n] != self.idx[n]:
                return true

        return false

    // names must be sorted; reports the first clash
    fn untracked_clash(names: List[String]) Bool:
        for n in names:
            if not self.idx.contains(n) and self.wt.contains(n):
                self.err("untracked file would be overwritten: " + n)
                return true

        return false

    // Replaces the index with target and rewrites the working tree.
    var fn materialize(target: Map[String, String], overrides: Map[String, String]) Unit:
        for n in self.idx.keys():
            self.wt.remove(n)
        for n in target.keys():
            self.wt[n.clone()] = target[n].clone()
        for n in overrides.keys():
            self.wt[n.clone()] = overrides[n].clone()
        self.idx = target.clone()

    var fn reset_to(id: String) Unit:
        for n in self.head_tree().keys():
            self.wt.remove(n)
        self.materialize(tree_of(self.commits, id), Map[String, String]())
        self.set_head(id)
        self.merging = false
        self.merge_other = ""
        self.merge_branch = ""
        self.conflicts = Map[String, String]()

    var fn put_file(name: String, block: String, append: Bool) Unit:
        if append:
            var cur = ""
            if self.wt.contains(name):
                cur = self.wt[name].clone()
            self.wt[name] = cur + block
        else:
            self.wt[name] = block

    fn cmd_ls() Unit:
        let names = sorted_keys(self.wt)
        if names.length() == 0:
            print("(empty)")
        for n in names:
            print(n)

    fn cmd_cat(args: List[String]) Unit:
        if args.length() != 1:
            self.err("usage: cat FILE")
            return

        if not self.wt.contains(args[0]):
            self.err("no such file: " + args[0])
            return

        for l in lines_of(self.wt[args[0]]):
            print(l)

    var fn cmd_rm(args: List[String]) Unit:
        if args.length() == 0:
            self.err("usage: rm FILE...")
            return

        for a in args:
            if not self.wt.contains(a):
                self.err("no such file: " + a)
                return

            self.wt.remove(a)

    var fn cmd_mv(args: List[String]) Unit:
        if args.length() != 2:
            self.err("usage: mv OLD NEW")
            return

        let old = args[0].clone()
        let new = args[1].clone()

        if not self.wt.contains(old):
            self.err("no such file: " + old)
            return

        let content = self.wt[old].clone()
        self.wt.remove(old)
        self.wt[new] = content

    var fn cmd_add(args: List[String]) Unit:
        if args.length() == 0:
            self.err("usage: add PATH...")
            return

        for p in args:
            if p == ".":
                for n in sorted_keys(self.conflicts):
                    if self.wt.contains(n) or self.idx.contains(n):
                        self.conflicts.remove(n)
                for n in self.wt.keys():
                    self.idx[n.clone()] = self.wt[n].clone()
                for n in self.idx.keys():
                    if not self.wt.contains(n):
                        self.idx.remove(n)
            else if self.wt.contains(p):
                self.idx[p.clone()] = self.wt[p].clone()
                self.conflicts.remove(p)
            else if self.idx.contains(p):
                self.idx.remove(p.clone())
                self.conflicts.remove(p)
            else if self.conflicts.contains(p):
                self.conflicts.remove(p)
            else:
                self.err("pathspec '" + p + "' did not match any files")
                return

    fn cmd_status() Unit:
        if self.on_branch:
            print("On branch " + self.branch)
        else:
            print("HEAD detached at " + short_id(self.detached))

        if self.merging:
            print("merging: " + self.merge_branch)

        let ht = self.head_tree()
        var names = ht.keys()
        for n in self.idx.keys():
            if not ht.contains(n):
                names.append(n)
        names.sort()

        var staged = List[String]()

        for n in names:
            if self.conflicts.contains(n):
                continue

            let ih = self.idx.contains(n)
            let hh = ht.contains(n)

            if ih and not hh:
                staged.append("new file: " + n)
            else if hh and not ih:
                staged.append("deleted: " + n)
            else if ih and hh:
                if self.idx[n] != ht[n]:
                    staged.append("modified: " + n)

        var unstaged = List[String]()

        for n in sorted_keys(self.idx):
            if self.conflicts.contains(n):
                continue

            if not self.wt.contains(n):
                unstaged.append("deleted: " + n)
            else if self.wt[n] != self.idx[n]:
                unstaged.append("modified: " + n)

        var conflicted = List[String]()
        for n in sorted_keys(self.conflicts):
            conflicted.append("unmerged: " + n)

        var untracked = List[String]()
        for n in sorted_keys(self.wt):
            if not self.idx.contains(n) and not self.conflicts.contains(n):
                untracked.append(n)

        if (
            staged.length() + unstaged.length() + conflicted.length() + untracked.length() == 0
        ):
            print("nothing to commit, working tree clean")
            return

        if staged.length() > 0:
            print("staged:")
            for s in staged:
                print("  " + s)

        if unstaged.length() > 0:
            print("unstaged:")
            for s in unstaged:
                print("  " + s)

        if conflicted.length() > 0:
            print("conflicts:")
            for s in conflicted:
                print("  " + s)

        if untracked.length() > 0:
            print("untracked:")
            for s in untracked:
                print("  " + s)

    var fn cmd_commit(msg: String) Unit:
        if msg == "":
            self.err("empty commit message")
            return

        if self.conflicts.length() > 0:
            self.err("unresolved conflicts: " + sorted_keys(self.conflicts).join(" "))
            return

        let head = self.head_id()

        if self.merging:
            var parents = List[String]()
            parents.append(head.clone())
            parents.append(self.merge_other.clone())

            let id = self.make_commit(self.idx.clone(), parents, msg.clone())
            self.set_head(id.clone())
            self.merging = false
            self.merge_other = ""
            self.merge_branch = ""
            self.conflicts = Map[String, String]()
            print("[" + self.label() + " " + short_id(id) + "] " + msg)
            return

        if same_tree(self.idx, self.head_tree()):
            self.err("nothing to commit")
            return

        var parents = List[String]()
        if head != "":
            parents.append(head.clone())

        let root = parents.length() == 0
        let id = self.make_commit(self.idx.clone(), parents, msg.clone())
        self.set_head(id.clone())

        if root:
            print("[" + self.label() + " (root-commit) " + short_id(id) + "] " + msg)
        else:
            print("[" + self.label() + " " + short_id(id) + "] " + msg)

    fn cmd_log(args: List[String]) Unit:
        var limit = -1

        if args.length() == 2 and args[0] == "-n" and all_digits(args[1]):
            limit = args[1].parse_int().get(0)
        else if args.length() != 0:
            self.err("usage: log [-n N]")
            return

        let head = self.head_id()

        if head == "":
            self.err("no commits yet")
            return

        var pos = List[Int]()
        for id in ancestors(self.commits, head):
            pos.append(find_commit(self.commits, id))
        pos.sort(fn a, b: b - a)

        var shown = 0

        for p in pos:
            if limit >= 0 and shown >= limit:
                break

            let c = self.commits[p]
            var line = short_id(c.id) + " " + c.message
            if c.parents.length() == 2:
                line += (
                    " (merge "
                    + short_id(c.parents[0])
                    + " "
                    + short_id(c.parents[1])
                    + ")"
                )
            print(line)
            shown += 1

    fn cmd_diff(args: List[String]) Unit:
        if args.length() > 2:
            self.err("usage: diff [REF [REF]]")
            return

        var left = Map[String, String]()
        var right = Map[String, String]()

        if args.length() == 0:
            left = self.idx.clone()
            right = self.wt.clone()
        else if args.length() == 1:
            let id = self.resolve(args[0])
            if id == "":
                return

            left = tree_of(self.commits, id)
            right = self.wt.clone()
        else:
            let a = self.resolve(args[0])
            if a == "":
                return

            let b = self.resolve(args[1])
            if b == "":
                return

            left = tree_of(self.commits, a)
            right = tree_of(self.commits, b)

        var names = left.keys()
        for n in right.keys():
            if not left.contains(n):
                names.append(n)
        names.sort()

        var any = false

        for n in names:
            let lh = left.contains(n)
            let rh = right.contains(n)
            var lt = ""
            var rt = ""
            if lh:
                lt = left[n].clone()
            if rh:
                rt = right[n].clone()
            if lh and rh and lt == rt:
                continue

            any = true
            print("diff " + n)
            if not lh:
                print("new file")
            if not rh:
                print("deleted file")
            print_line_diff(lines_of(lt), lines_of(rt))

        if not any:
            print("(no differences)")

    fn show(args: List[String]) Unit:
        if args.length() != 1:
            self.err("usage: show REF")
            return

        let id = self.resolve(args[0])
        if id == "":
            return

        let p = find_commit(self.commits, id)
        let c = self.commits[p]
        print("commit " + id)
        print("tree " + tree_hash(c.tree))
        for par in c.parents:
            print("parent " + par)
        print("message: " + c.message)
        print("files:")
        for nm in sorted_keys(c.tree):
            print("  " + nm + " " + short_id(fnv_hex(c.tree[nm])))

    var fn create_branch(name: String) Bool:
        if not valid_name(name):
            self.err("invalid branch name '" + name + "'")
            return false

        if self.branches.contains(name):
            self.err("branch '" + name + "' already exists")
            return false

        let head = self.head_id()

        if head == "":
            self.err("no commits yet")
            return false

        self.branches[name] = head
        return true

    var fn delete_branch(name: String) Unit:
        if not self.branches.contains(name):
            self.err("branch '" + name + "' not found")
            return

        if self.on_branch and self.branch == name:
            self.err("cannot delete the current branch '" + name + "'")
            return

        let bid = self.branches[name].clone()
        let head = self.head_id()
        let merged = (
            head != ""
            and bid != ""
            and ancestors(self.commits, head).contains(bid)
        )

        if not merged:
            self.err("branch '" + name + "' is not fully merged")
            return

        self.branches.remove(name.clone())
        print("Deleted branch " + name + " (was " + short_id(bid) + ").")

    var fn cmd_branch(args: List[String]) Unit:
        if args.length() == 0:
            if not self.on_branch:
                print("* (HEAD detached at " + short_id(self.detached) + ")")

            for n in sorted_keys(self.branches):
                if self.on_branch and self.branch == n:
                    print("* " + n)
                else:
                    print("  " + n)
        else if args.length() == 1:
            self.create_branch(args[0].clone())
        else if args.length() == 2 and args[0] == "-d":
            self.delete_branch(args[1].clone())
        else:
            self.err("usage: branch [NAME | -d NAME]")

    var fn cmd_tag(args: List[String]) Unit:
        if args.length() == 0:
            for n in sorted_keys(self.tags):
                print(n)
            return

        if args.length() > 2:
            self.err("usage: tag [NAME [REF]]")
            return

        let name = args[0].clone()

        if not valid_name(name):
            self.err("invalid tag name '" + name + "'")
            return

        if self.tags.contains(name):
            self.err("tag '" + name + "' already exists")
            return

        var refname = "HEAD"
        if args.length() == 2:
            refname = args[1].clone()

        if (args.length() == 1 or refname == "HEAD") and self.head_id() == "":
            self.err("no commits yet")
            return

        let id = self.resolve(refname)
        if id == "":
            return

        self.tags[name] = id

    var fn cmd_checkout(args: List[String]) Unit:
        if args.length() == 2 and args[0] == "-b":
            let name = args[1].clone()
            if not self.create_branch(name.clone()):
                return

            if self.dirty():
                self.err("local changes would be overwritten")
                return

            self.on_branch = true
            self.branch = name.clone()
            print("Switched to a new branch '" + name + "'")
        else if args.length() == 1:
            let target = args[0].clone()

            if self.merging:
                self.err("merge in progress")
                return

            if self.branches.contains(target):
                if self.on_branch and self.branch == target:
                    print("Already on '" + target + "'")
                    return

                if self.dirty():
                    self.err("local changes would be overwritten")
                    return

                let tree = tree_of(self.commits, self.branches[target])
                if self.untracked_clash(sorted_keys(tree)):
                    return

                self.materialize(tree, Map[String, String]())
                self.on_branch = true
                self.branch = target.clone()
                print("Switched to branch '" + target + "'")
                return

            let id = self.resolve(target)
            if id == "":
                return

            if self.dirty():
                self.err("local changes would be overwritten")
                return

            let tree = tree_of(self.commits, id)
            if self.untracked_clash(sorted_keys(tree)):
                return

            self.materialize(tree, Map[String, String]())
            self.on_branch = false
            self.detached = id.clone()
            print("HEAD is now at " + short_id(id) + " " + message_of(self.commits, id))
        else:
            self.err("usage: checkout REF | checkout -b NAME")

    var fn cmd_reset(args: List[String]) Unit:
        if args.length() == 0 or args[0] != "--hard" or args.length() > 2:
            self.err("usage: reset --hard [REF]")
            return

        var refname = "HEAD"
        if args.length() == 2:
            refname = args[1].clone()

        if (args.length() == 1 or refname == "HEAD") and self.head_id() == "":
            self.err("no commits yet")
            return

        let id = self.resolve(refname)
        if id == "":
            return

        self.reset_to(id.clone())
        print("HEAD is now at " + short_id(id) + " " + message_of(self.commits, id))

    var fn merge_abort() Unit:
        if not self.merging:
            self.err("no merge in progress")
            return

        self.reset_to(self.head_id())
        print("Merge aborted.")

    var fn cmd_merge(args: List[String]) Unit:
        if args.length() == 1 and args[0] == "--abort":
            self.merge_abort()
            return

        if args.length() != 1:
            self.err("usage: merge BRANCH")
            return

        let name = args[0].clone()

        if self.merging:
            self.err("merge in progress")
            return

        let cur = self.head_id()

        if cur == "":
            self.err("no commits yet")
            return

        if not self.branches.contains(name) or self.branches[name] == "":
            self.err("unknown branch '" + name + "'")
            return

        let other = self.branches[name].clone()

        if self.dirty():
            self.err("local changes would be overwritten")
            return

        if ancestors(self.commits, cur).contains(other):
            print("Already up to date.")
            return

        if ancestors(self.commits, other).contains(cur):
            let tree = tree_of(self.commits, other)
            if self.untracked_clash(sorted_keys(tree)):
                return

            self.materialize(tree, Map[String, String]())
            self.set_head(other)
            print("Fast-forward")
            return

        let base = merge_base(self.commits, cur, other)
        let bt = tree_of(self.commits, base)
        let ot = self.head_tree()
        let tt = tree_of(self.commits, other)
        var seen = Set[String]()
        for k in bt.keys():
            seen.add(k)
        for k in ot.keys():
            seen.add(k)
        for k in tt.keys():
            seen.add(k)

        var result = Map[String, String]()
        var overrides = Map[String, String]()
        var conflicts = Map[String, String]()

        for n in sorted_set(seen):
            let be = ent(bt, n)
            let oe = ent(ot, n)
            let te = ent(tt, n)

            if ent_eq(oe, te):
                if oe.has:
                    result[n.clone()] = oe.text.clone()
            else if ent_eq(oe, be):
                if te.has:
                    result[n.clone()] = te.text.clone()
            else if ent_eq(te, be):
                if oe.has:
                    result[n.clone()] = oe.text.clone()
            else if oe.has != te.has:
                conflicts[n.clone()] = "modify/delete"

                if oe.has:
                    result[n.clone()] = oe.text.clone()
                    overrides[n.clone()] = oe.text.clone()
                else:
                    overrides[n.clone()] = te.text.clone()
            else:
                let m = three_way(
                    lines_of(be.text), lines_of(oe.text), lines_of(te.text), name
                )

                if m.conflict:
                    if be.has:
                        conflicts[n.clone()] = "content"
                    else:
                        conflicts[n.clone()] = "add/add"

                    result[n.clone()] = oe.text.clone()
                    overrides[n.clone()] = m.text.clone()
                else:
                    result[n.clone()] = m.text.clone()

        var touched = Set[String]()
        for k in result.keys():
            touched.add(k)
        for k in overrides.keys():
            touched.add(k)
        if self.untracked_clash(sorted_set(touched)):
            return

        self.materialize(result, overrides)

        if conflicts.length() == 0:
            var parents = List[String]()
            parents.append(cur.clone())
            parents.append(other.clone())

            let msg = "Merge branch '" + name + "'"
            let id = self.make_commit(self.idx.clone(), parents, msg.clone())
            self.set_head(id.clone())
            print("Merge made by the 'three-way' strategy.")
            print("[" + self.label() + " " + short_id(id) + "] " + msg)
        else:
            self.merging = true
            self.merge_other = other
            self.merge_branch = name
            self.conflicts = conflicts.clone()

            for n in sorted_keys(conflicts):
                let kind = conflicts[n].clone()

                if kind == "modify/delete":
                    print("CONFLICT (modify/delete): " + n)
                else:
                    print("CONFLICT (" + kind + "): Merge conflict in " + n)

            print("Automatic merge failed; fix conflicts and then commit the result.")

    var fn run(cmd: String, args: List[String], rest: String) Unit:
        if cmd == "ls":
            self.cmd_ls()
        else if cmd == "cat":
            self.cmd_cat(args)
        else if cmd == "rm":
            self.cmd_rm(args)
        else if cmd == "mv":
            self.cmd_mv(args)
        else if cmd == "add":
            self.cmd_add(args)
        else if cmd == "status":
            self.cmd_status()
        else if cmd == "commit":
            self.cmd_commit(rest)
        else if cmd == "log":
            self.cmd_log(args)
        else if cmd == "diff":
            self.cmd_diff(args)
        else if cmd == "show":
            self.show(args)
        else if cmd == "branch":
            self.cmd_branch(args)
        else if cmd == "tag":
            self.cmd_tag(args)
        else if cmd == "checkout":
            self.cmd_checkout(args)
        else if cmd == "merge":
            self.cmd_merge(args)
        else if cmd == "reset":
            self.cmd_reset(args)
        else:
            self.err("unknown command '" + cmd + "'")

export fn main() Int:
    let raw = read_all(stdin()).get()
    let text = raw.decode_utf8().get("")
    let parts = text.split("\n")
    var n = parts.length()
    if n > 0 and parts[n - 1] == "":
        n -= 1

    var repo = Repo(
        wt: Map[String, String](), idx: Map[String, String](), commits: List[Commit](),
        branches: Map[String, String](), tags: Map[String, String](), on_branch: true,
        branch: "main", detached: "", merging: false, merge_other: "", merge_branch: "",
        conflicts: Map[String, String]()
    )
    repo.branches["main"] = ""

    var i = 0

    while i < n:
        let line = parts[i].clone()
        i += 1

        let t = line.trim()
        if t == "" or t.starts_with("#"):
            continue

        print("> " + rtrim(line))

        let words = split_words(t)
        let cmd = words[0].clone()
        var args = List[String]()
        for k in 1..words.length():
            args.append(words[k].clone())

        if cmd == "write" or cmd == "append":
            if args.length() != 1:
                repo.err("usage: " + cmd + " FILE")
            else:
                var block = ""

                while i < n and parts[i] != ".":
                    block += parts[i] + "\n"
                    i += 1

                if i < n:
                    i += 1
                repo.put_file(args[0].clone(), block, cmd == "append")
        else:
            let rest = t.slice(cmd.length(), t.length()).get("").trim()
            repo.run(cmd, args, rest)

    return 0
