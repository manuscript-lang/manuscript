import stdin, stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"
import wrapping_multiply, bit_xor, bit_and, shift_right from "@std/math/math.ms"

let FNV_OFFSET = -3750763034362895579
let FNV_PRIME = 1099511628211
let HEX_DIGITS = "0123456789abcdef"
let NAME_FIRST = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/"
let NAME_REST = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-"
let DIGITS = "0123456789"

type Commit:
    tree: Map[String, String]
    parents: List[String]
    message: String
    seq: Int

type Repo:
    files: Map[String, String]
    index: Map[String, String]
    commits: Map[String, Commit]
    branches: Map[String, String]
    tags: Map[String, String]
    head_branch: String
    head_id: String
    seq_count: Int
    merging: Bool
    merge_other: String
    merge_branch: String
    conflicts: Map[String, String]

type MergeText:
    text: String
    clean: Bool

type MergeResult:
    tree: Map[String, String]
    overrides: Map[String, String]
    kinds: Map[String, String]

// ---------- output helpers ----------

fn say(text: String) Unit:
    stdout().write("{text}\n").get()

fn err(msg: String) Unit:
    say("error: {msg}")

// ---------- hashing ----------

fn fnv(text: String) Int:
    var h = FNV_OFFSET
    for b in text.to_bytes().values():
        h = bit_xor(h, b.to_int())
        h = wrapping_multiply(h, FNV_PRIME)
    return h

fn hex16(h: Int) String:
    let digits = HEX_DIGITS.chars()
    var out = ""
    var k = 15
    while k >= 0:
        let nib = bit_and(shift_right(h, k * 4), 15)
        out = "{out}{digits[nib]}"
        k -= 1
    return out

fn short(id: String) String:
    var out = ""
    var i = 0
    for c in id.chars():
        if i < 7:
            out = "{out}{c}"
        i += 1
    return out

fn tree_text(tree: Map[String, String]) String:
    var text = ""
    for name in tree.keys().sorted():
        let content = tree.get_or(name, "")
        let h = hex16(fnv(content))
        text = "{text}{name} {h}\n"
    return text

fn tree_hash(tree: Map[String, String]) String:
    let text = tree_text(tree)
    return hex16(fnv(text))

fn commit_id(tree: Map[String, String], parents: List[String], message: String) String:
    let th = tree_hash(tree)
    var text = "tree {th}\n"
    for p in parents:
        text = "{text}parent {p}\n"
    text = "{text}\n{message}\n"
    return hex16(fnv(text))

// ---------- small string / list helpers ----------

fn in_set(c: String, set: String) Bool:
    return set.index_of(c).get(-1) >= 0

fn is_space(c: String) Bool:
    return c == " " or c == "\t" or c == "\r" or c == "\n"

fn all_digits(s: String) Bool:
    if s.length() == 0:
        return false
    for c in s.chars():
        if not in_set(c, DIGITS):
            return false
    return true

fn is_hex_candidate(s: String) Bool:
    if s.chars().length() < 4:
        return false
    for c in s.chars():
        if not in_set(c, HEX_DIGITS):
            return false
    return true

fn valid_name(name: String) Bool:
    let cs = name.chars()
    if cs.length() == 0:
        return false
    if not in_set(cs[0], NAME_FIRST):
        return false
    var i = 1
    while i < cs.length():
        if not in_set(cs[i], NAME_REST):
            return false
        i += 1
    return true

// Splits command words on whitespace.
fn words(line: String) List[String]:
    var out = List[String]()
    var cur = ""
    for c in line.chars():
        if is_space(c):
            if cur != "":
                out.append(cur.clone())
                cur = ""
        else:
            cur = "{cur}{c}"
    if cur != "":
        out.append(cur.clone())
    return out

// The text after the first word of a line, with leading blanks skipped.
fn rest_after_word(line: String) String:
    let cs = line.chars()
    var k = 0
    while k < cs.length() and is_space(cs[k]):
        k += 1
    while k < cs.length() and not is_space(cs[k]):
        k += 1
    var out = ""
    while k < cs.length():
        out = "{out}{cs[k]}"
        k += 1
    return out

fn tail(xs: List[String]) List[String]:
    var out = List[String]()
    var i = 1
    while i < xs.length():
        out.append(xs[i].clone())
        i += 1
    return out

// Splits content into lines; a trailing newline does not make an extra line.
fn split_lines(content: String) List[String]:
    let parts = content.split("\n")
    var out = List[String]()
    let n = parts.length()
    var i = 0
    while i < n:
        if i < n - 1 or parts[i] != "":
            out.append(parts[i].clone())
        i += 1
    return out

fn join_lines(xs: List[String]) String:
    var out = ""
    for x in xs:
        out = "{out}{x}\n"
    return out

fn list_eq(a: List[String], b: List[String]) Bool:
    if a.length() != b.length():
        return false
    var i = 0
    while i < a.length():
        if a[i] != b[i]:
            return false
        i += 1
    return true

fn sub_lines(xs: List[String], from: Int, to: Int) List[String]:
    var out = List[String]()
    var i = from
    while i < to:
        out.append(xs[i].clone())
        i += 1
    return out

// True when both maps agree on presence and content of every name.
fn tree_eq(a: Map[String, String], b: Map[String, String]) Bool:
    if a.length() != b.length():
        return false
    for name in a.keys():
        if not b.contains(name):
            return false
        if a.get_or(name, "") != b.get_or(name, ""):
            return false
    return true

// Presence and content of one name agree in both maps.
fn entry_eq(a: Map[String, String], b: Map[String, String], name: String) Bool:
    if a.contains(name) != b.contains(name):
        return false
    return a.get_or(name, "") == b.get_or(name, "")

fn union_names(a: Map[String, String], b: Map[String, String]) List[String]:
    var names = a.keys()
    for n in b.keys():
        if not a.contains(n):
            names.append(n)
    names.sort()
    return names

// ---------- diff ----------

// Flat LCS table: entry (i, j) is at i * (m + 1) + j.
fn lcs_table(a: List[String], b: List[String]) List[Int]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var table = List[Int]()
    var z = 0
    while z < (n + 1) * w:
        table.append(0)
        z += 1
    var i = n - 1
    while i >= 0:
        var j = m - 1
        while j >= 0:
            if a[i] == b[j]:
                table[i * w + j] = table[(i + 1) * w + j + 1] + 1
            else:
                let down = table[(i + 1) * w + j]
                let right = table[i * w + j + 1]
                if down >= right:
                    table[i * w + j] = down
                else:
                    table[i * w + j] = right
            j -= 1
        i -= 1
    return table

// Matching pairs as a flat list [a0, b0, a1, b1, ...].
fn matching(a: List[String], b: List[String]) List[Int]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    let table = lcs_table(a, b)
    var out = List[Int]()
    var x = 0
    var y = 0
    while x < n and y < m:
        if a[x] == b[y]:
            out.append(x)
            out.append(y)
            x += 1
            y += 1
        else if table[(x + 1) * w + y] >= table[x * w + y + 1]:
            x += 1
        else:
            y += 1
    return out

fn line_diff(a: List[String], b: List[String]) String:
    let pairs = matching(a, b)
    let n = a.length()
    let m = b.length()
    var out = ""
    var ia = 0
    var jb = 0
    var k = 0
    while k < pairs.length():
        let pa = pairs[k]
        let pb = pairs[k + 1]
        while ia < pa:
            out = "{out}- {a[ia]}\n"
            ia += 1
        while jb < pb:
            out = "{out}+ {b[jb]}\n"
            jb += 1
        out = "{out}  {a[pa]}\n"
        ia = pa + 1
        jb = pb + 1
        k += 2
    while ia < n:
        out = "{out}- {a[ia]}\n"
        ia += 1
    while jb < m:
        out = "{out}+ {b[jb]}\n"
        jb += 1
    return out

// ---------- three-way line merge ----------

fn resolve_chunk(bc: List[String], oc: List[String], tc: List[String], branch: String) MergeText:
    if list_eq(oc, bc):
        return MergeText(text: join_lines(tc), clean: true)
    if list_eq(tc, bc):
        return MergeText(text: join_lines(oc), clean: true)
    if list_eq(oc, tc):
        return MergeText(text: join_lines(oc), clean: true)
    let ours_text = join_lines(oc)
    let theirs_text = join_lines(tc)
    let text = "<<<<<<< HEAD\n{ours_text}=======\n{theirs_text}>>>>>>> {branch}\n"
    return MergeText(text: text, clean: false)

fn merge_lines(base: List[String], ours: List[String], theirs: List[String], branch: String) MergeText:
    let mo = matching(base, ours)
    let mt = matching(base, theirs)
    let nb = base.length()
    var o_of = List[Int]()
    var t_of = List[Int]()
    var b = 0
    while b < nb:
        o_of.append(-1)
        t_of.append(-1)
        b += 1
    var k = 0
    while k < mo.length():
        o_of[mo[k]] = mo[k + 1]
        k += 2
    k = 0
    while k < mt.length():
        t_of[mt[k]] = mt[k + 1]
        k += 2
    var out = ""
    var clean = true
    var pb = -1
    var po = -1
    var pt = -1
    b = 0
    while b < nb:
        let o = o_of[b]
        let t = t_of[b]
        if o >= 0 and t >= 0:
            let chunk = resolve_chunk(sub_lines(base, pb + 1, b), sub_lines(ours, po + 1, o), sub_lines(theirs, pt + 1, t), branch)
            out = "{out}{chunk.text}"
            if not chunk.clean:
                clean = false
            out = "{out}{base[b]}\n"
            pb = b
            po = o
            pt = t
        b += 1
    let last = resolve_chunk(sub_lines(base, pb + 1, nb), sub_lines(ours, po + 1, ours.length()), sub_lines(theirs, pt + 1, theirs.length()), branch)
    out = "{out}{last.text}"
    if not last.clean:
        clean = false
    return MergeText(text: out, clean: clean)

// ---------- repository ----------

impl Repo:
    fn commit_tree(id: String) Map[String, String]:
        if let c = self.commits.get(id):
            return c.tree.clone()
        return Map[String, String]()

    fn parents_of(id: String) List[String]:
        if let c = self.commits.get(id):
            return c.parents.clone()
        return List[String]()

    fn message_of(id: String) String:
        if let c = self.commits.get(id):
            return c.message.clone()
        return ""

    fn seq_of(id: String) Int:
        if let c = self.commits.get(id):
            return c.seq
        return 0

    fn head_commit() String:
        if self.head_branch != "":
            return self.branches.get_or(self.head_branch, "")
        return self.head_id.clone()

    fn head_tree() Map[String, String]:
        return self.commit_tree(self.head_commit())

    fn current_name() String:
        if self.head_branch != "":
            return self.head_branch.clone()
        return "detached"

    var fn set_head_commit(id: String) Unit:
        if self.head_branch != "":
            self.branches[self.head_branch.clone()] = id.clone()
        else:
            self.head_id = id.clone()

    fn ancestors(start: String) List[String]:
        var seen = List[String]()
        if start == "":
            return seen
        seen.append(start.clone())
        var i = 0
        while i < seen.length():
            let cur = seen[i].clone()
            i += 1
            for p in self.parents_of(cur):
                if not seen.contains(p):
                    seen.append(p.clone())
        return seen

    fn merge_base(cur: String, other: String) String:
        let ac = self.ancestors(cur)
        let ao = self.ancestors(other)
        var best = ""
        var best_seq = -1
        for id in ac:
            if ao.contains(id):
                let s = self.seq_of(id)
                if s > best_seq:
                    best = id.clone()
                    best_seq = s
        return best

    fn is_ancestor_or_same(anc: String, of: String) Bool:
        if anc == "":
            return false
        return self.ancestors(of).contains(anc)

    fn prefix_matches(prefix: String) List[String]:
        var out = List[String]()
        for id in self.commits.keys():
            if id.starts_with(prefix):
                out.append(id)
        return out

    fn base_lookup(name: String) String:
        if name == "HEAD":
            return self.head_commit()
        if self.branches.contains(name):
            let b = self.branches.get_or(name, "")
            if b != "":
                return b
        if self.tags.contains(name):
            return self.tags.get_or(name, "")
        if is_hex_candidate(name):
            let found = self.prefix_matches(name)
            if found.length() == 1:
                return found[0].clone()
        return ""

    fn resolve(rev: String) String:
        let parts = rev.split("~")
        if parts.length() == 1:
            return self.base_lookup(rev)
        if parts.length() != 2:
            return ""
        if not all_digits(parts[1]):
            return ""
        let steps = parts[1].parse_int().get(-1)
        if steps < 0:
            return ""
        var id = self.base_lookup(parts[0])
        var k = 0
        while k < steps:
            let ps = self.parents_of(id)
            if ps.length() == 0:
                return ""
            id = ps[0].clone()
            k += 1
        return id

    fn ref_error(rev: String) String:
        let parts = rev.split("~")
        let base = parts[0].clone()
        if is_hex_candidate(base):
            if self.prefix_matches(base).length() > 1:
                return "ambiguous revision '{rev}'"
        return "unknown revision '{rev}'"

    fn dirty() Bool:
        if not tree_eq(self.index, self.head_tree()):
            return true
        for name in self.index.keys():
            if not self.files.contains(name):
                return true
            if self.index.get_or(name, "") != self.files.get_or(name, ""):
                return true
        return false

    // First name (sorted) that is not indexed but exists in the working tree.
    fn first_untracked(names: List[String]) String:
        for name in names.sorted():
            if not self.index.contains(name) and self.files.contains(name):
                return name.clone()
        return ""

    // Replaces index and working files of the tracked names with the given tree.
    var fn switch_to(tree: Map[String, String]) Unit:
        for name in self.index.keys():
            self.files.remove(name.clone())
        for name in tree.keys():
            self.files[name.clone()] = tree.get_or(name, "")
        self.index = tree.clone()

    // Moves HEAD's commit to id and resets index and working files to it.
    var fn hard_reset_to(id: String) Unit:
        let old_tree = self.head_tree()
        for name in self.index.keys():
            self.files.remove(name.clone())
        for name in old_tree.keys():
            self.files.remove(name.clone())
        let new_tree = self.commit_tree(id)
        for name in new_tree.keys():
            self.files[name.clone()] = new_tree.get_or(name, "")
        self.index = new_tree
        self.set_head_commit(id)
        self.merging = false
        self.merge_other = ""
        self.merge_branch = ""
        self.conflicts = Map[String, String]()

    var fn make_commit(tree: Map[String, String], parents: List[String], message: String) String:
        let id = commit_id(tree, parents, message)
        if not self.commits.contains(id):
            self.seq_count += 1
            self.commits[id.clone()] = Commit(tree: tree.clone(), parents: parents.clone(), message: message.clone(), seq: self.seq_count)
        return id

    var fn write_file(name: String, content: String, append: Bool) Unit:
        if append:
            let old = self.files.get_or(name, "")
            self.files[name.clone()] = "{old}{content}"
        else:
            self.files[name.clone()] = content.clone()

    var fn cmd_rm(args: List[String]) Unit:
        if args.length() == 0:
            err("usage: rm FILE...")
            return
        for name in args:
            if not self.files.contains(name):
                err("no such file: {name}")
                return
            self.files.remove(name.clone())

    var fn cmd_mv(args: List[String]) Unit:
        if args.length() != 2:
            err("usage: mv OLD NEW")
            return
        let old = args[0].clone()
        let new = args[1].clone()
        if not self.files.contains(old):
            err("no such file: {old}")
            return
        let content = self.files.get_or(old, "")
        self.files.remove(old.clone())
        self.files[new] = content

    fn cmd_cat(args: List[String]) Unit:
        if args.length() != 1:
            err("usage: cat FILE")
            return
        if not self.files.contains(args[0]):
            err("no such file: {args[0]}")
            return
        stdout().write(self.files.get_or(args[0], "")).get()

    fn cmd_ls() Unit:
        let names = self.files.keys().sorted()
        if names.length() == 0:
            say("(empty)")
            return
        for name in names:
            say(name)

    var fn cmd_add(args: List[String]) Unit:
        if args.length() == 0:
            err("usage: add PATH...")
            return
        for p in args:
            if p == ".":
                var resolved = List[String]()
                for name in self.conflicts.keys():
                    if self.files.contains(name) or self.index.contains(name):
                        resolved.append(name.clone())
                for name in self.files.keys():
                    self.index[name.clone()] = self.files.get_or(name, "")
                for name in self.index.keys():
                    if not self.files.contains(name):
                        self.index.remove(name.clone())
                for name in resolved:
                    self.conflicts.remove(name.clone())
            else if self.files.contains(p):
                self.index[p.clone()] = self.files.get_or(p, "")
                self.conflicts.remove(p.clone())
            else if self.index.contains(p):
                self.index.remove(p.clone())
                self.conflicts.remove(p.clone())
            else if self.conflicts.contains(p):
                self.conflicts.remove(p.clone())
            else:
                err("pathspec '{p}' did not match any files")
                return

    fn cmd_status() Unit:
        if self.head_branch != "":
            say("On branch {self.head_branch}")
        else:
            say("HEAD detached at {short(self.head_id)}")
        if self.merging:
            say("merging: {self.merge_branch}")
        let ht = self.head_tree()
        var any = false

        var staged = List[String]()
        for name in union_names(ht, self.index):
            if self.conflicts.contains(name):
                continue
            let in_index = self.index.contains(name)
            let in_head = ht.contains(name)
            if in_index and not in_head:
                staged.append("new file: {name}")
            else if in_head and not in_index:
                staged.append("deleted: {name}")
            else if self.index.get_or(name, "") != ht.get_or(name, ""):
                staged.append("modified: {name}")

        var unstaged = List[String]()
        for name in self.index.keys().sorted():
            if self.conflicts.contains(name):
                continue
            if not self.files.contains(name):
                unstaged.append("deleted: {name}")
            else if self.files.get_or(name, "") != self.index.get_or(name, ""):
                unstaged.append("modified: {name}")

        var unmerged = List[String]()
        for name in self.conflicts.keys().sorted():
            unmerged.append("unmerged: {name}")

        var untracked = List[String]()
        for name in self.files.keys().sorted():
            if not self.index.contains(name) and not self.conflicts.contains(name):
                untracked.append(name.clone())

        if staged.length() > 0:
            any = true
            say("staged:")
            for l in staged:
                say("  {l}")
        if unstaged.length() > 0:
            any = true
            say("unstaged:")
            for l in unstaged:
                say("  {l}")
        if unmerged.length() > 0:
            any = true
            say("conflicts:")
            for l in unmerged:
                say("  {l}")
        if untracked.length() > 0:
            any = true
            say("untracked:")
            for l in untracked:
                say("  {l}")
        if not any:
            say("nothing to commit, working tree clean")

    fn cmd_diff(args: List[String]) Unit:
        if args.length() > 2:
            err("usage: diff [REF [REF]]")
            return
        var left = self.index.clone()
        var right = self.files.clone()
        if args.length() >= 1:
            let l = self.resolve(args[0])
            if l == "":
                err(self.ref_error(args[0]))
                return
            left = self.commit_tree(l)
            right = self.files.clone()
        if args.length() == 2:
            let r = self.resolve(args[1])
            if r == "":
                err(self.ref_error(args[1]))
                return
            right = self.commit_tree(r)
        var printed = false
        for name in union_names(left, right):
            if entry_eq(left, right, name):
                continue
            printed = true
            say("diff {name}")
            if not left.contains(name):
                say("new file")
            if not right.contains(name):
                say("deleted file")
            let a = split_lines(left.get_or(name, ""))
            let b = split_lines(right.get_or(name, ""))
            stdout().write(line_diff(a, b)).get()
        if not printed:
            say("(no differences)")

    fn cmd_log(args: List[String]) Unit:
        var limit = 9223372036854775807
        if args.length() == 2 and args[0] == "-n":
            if not all_digits(args[1]):
                err("usage: log [-n N]")
                return
            limit = args[1].parse_int().get(9223372036854775807)
        else if args.length() != 0:
            err("usage: log [-n N]")
            return
        let head = self.head_commit()
        if head == "":
            err("no commits yet")
            return
        let reach = self.ancestors(head)
        var by_seq = Map[Int, String]()
        var seqs = List[Int]()
        for id in reach:
            let s = self.seq_of(id)
            by_seq[s] = id.clone()
            seqs.append(s)
        seqs.sort()
        seqs.reverse()
        var shown = 0
        for s in seqs:
            if shown >= limit:
                break
            let id = by_seq.get_or(s, "")
            let ps = self.parents_of(id)
            let msg = self.message_of(id)
            if ps.length() == 2:
                let p0 = short(ps[0])
                let p1 = short(ps[1])
                say("{short(id)} {msg} (merge {p0} {p1})")
            else:
                say("{short(id)} {msg}")
            shown += 1

    fn cmd_show(args: List[String]) Unit:
        if args.length() != 1:
            err("usage: show REF")
            return
        let id = self.resolve(args[0])
        if id == "":
            err(self.ref_error(args[0]))
            return
        let tree = self.commit_tree(id)
        let ps = self.parents_of(id)
        say("commit {id}")
        say("tree {tree_hash(tree)}")
        for p in ps:
            say("parent {p}")
        say("message: {self.message_of(id)}")
        say("files:")
        for name in tree.keys().sorted():
            let h = hex16(fnv(tree.get_or(name, "")))
            say("  {name} {short(h)}")

    var fn create_branch(name: String) Bool:
        if not valid_name(name):
            err("invalid branch name '{name}'")
            return false
        if self.branches.contains(name):
            err("branch '{name}' already exists")
            return false
        let head = self.head_commit()
        if head == "":
            err("no commits yet")
            return false
        self.branches[name.clone()] = head.clone()
        return true

    var fn cmd_branch(args: List[String]) Unit:
        if args.length() == 0:
            if self.head_branch == "":
                say("* (HEAD detached at {short(self.head_id)})")
            for name in self.branches.keys().sorted():
                if self.head_branch == name:
                    say("* {name}")
                else:
                    say("  {name}")
            return
        if args.length() == 1:
            self.create_branch(args[0].clone())
            return
        if args.length() == 2 and args[0] == "-d":
            let name = args[1].clone()
            if not self.branches.contains(name):
                err("branch '{name}' not found")
                return
            if self.head_branch == name:
                err("cannot delete the current branch '{name}'")
                return
            let tip = self.branches.get_or(name, "")
            let merged = tip != "" and self.is_ancestor_or_same(tip, self.head_commit())
            if not merged:
                err("branch '{name}' is not fully merged")
                return
            self.branches.remove(name.clone())
            say("Deleted branch {name} (was {short(tip)}).")
            return
        err("usage: branch [NAME | -d NAME]")

    var fn cmd_tag(args: List[String]) Unit:
        if args.length() == 0:
            for name in self.tags.keys().sorted():
                say(name)
            return
        if args.length() > 2:
            err("usage: tag [NAME [REF]]")
            return
        let name = args[0].clone()
        if not valid_name(name):
            err("invalid tag name '{name}'")
            return
        if self.tags.contains(name):
            err("tag '{name}' already exists")
            return
        let rev = if_default_head(args)
        if (args.length() == 1 or args[1] == "HEAD") and self.head_commit() == "":
            err("no commits yet")
            return
        let id = self.resolve(rev)
        if id == "":
            err(self.ref_error(rev))
            return
        self.tags[name.clone()] = id

    var fn cmd_checkout(args: List[String]) Unit:
        if args.length() == 2 and args[0] == "-b":
            if self.create_branch(args[1].clone()):
                self.head_branch = args[1].clone()
                say("Switched to a new branch '{args[1]}'")
            return
        if args.length() != 1:
            err("usage: checkout REF | checkout -b NAME")
            return
        let target = args[0].clone()
        if self.merging:
            err("merge in progress")
            return
        if self.branches.contains(target):
            if self.head_branch == target:
                say("Already on '{target}'")
                return
            let tree = self.commit_tree(self.branches.get_or(target, ""))
            if self.dirty():
                err("local changes would be overwritten")
                return
            let u = self.first_untracked(tree.keys())
            if u != "":
                err("untracked file would be overwritten: {u}")
                return
            self.switch_to(tree)
            self.head_branch = target.clone()
            say("Switched to branch '{target}'")
            return
        let id = self.resolve(target)
        if id == "":
            err(self.ref_error(target))
            return
        let tree = self.commit_tree(id)
        if self.dirty():
            err("local changes would be overwritten")
            return
        let u = self.first_untracked(tree.keys())
        if u != "":
            err("untracked file would be overwritten: {u}")
            return
        self.switch_to(tree)
        self.head_branch = ""
        self.head_id = id.clone()
        say("HEAD is now at {short(id)} {self.message_of(id)}")

    var fn cmd_reset(args: List[String]) Unit:
        if args.length() == 0 or args.length() > 2 or args[0] != "--hard":
            err("usage: reset --hard [REF]")
            return
        var id = self.head_commit()
        if args.length() == 2:
            id = self.resolve(args[1])
            if id == "":
                err(self.ref_error(args[1]))
                return
        else if id == "":
            err("no commits yet")
            return
        self.hard_reset_to(id)
        say("HEAD is now at {short(id)} {self.message_of(id)}")

    var fn cmd_merge_abort() Unit:
        if not self.merging:
            err("no merge in progress")
            return
        self.hard_reset_to(self.head_commit())
        say("Merge aborted.")

    var fn cmd_merge(args: List[String]) Unit:
        if args.length() == 1 and args[0] == "--abort":
            self.cmd_merge_abort()
            return
        if args.length() != 1:
            err("usage: merge BRANCH")
            return
        let name = args[0].clone()
        if self.merging:
            err("merge in progress")
            return
        let cur = self.head_commit()
        if cur == "":
            err("no commits yet")
            return
        if not self.branches.contains(name) or self.branches.get_or(name, "") == "":
            err("unknown branch '{name}'")
            return
        let other = self.branches.get_or(name, "")
        if self.dirty():
            err("local changes would be overwritten")
            return
        if other == cur or self.is_ancestor_or_same(other, cur):
            say("Already up to date.")
            return
        if self.is_ancestor_or_same(cur, other):
            let tree = self.commit_tree(other)
            let u = self.first_untracked(tree.keys())
            if u != "":
                err("untracked file would be overwritten: {u}")
                return
            self.switch_to(tree)
            self.set_head_commit(other)
            say("Fast-forward")
            return
        let base = self.merge_base(cur, other)
        let result = self.three_way(base, cur, other, name)
        var targets = result.tree.keys()
        for k in result.overrides.keys():
            targets.append(k)
        let u = self.first_untracked(targets)
        if u != "":
            err("untracked file would be overwritten: {u}")
            return
        for k in self.index.keys():
            if not result.tree.contains(k):
                self.files.remove(k.clone())
        for k in result.tree.keys():
            if not result.kinds.contains(k):
                self.files[k.clone()] = result.tree.get_or(k, "")
        for k in result.overrides.keys():
            self.files[k.clone()] = result.overrides.get_or(k, "")
        self.index = result.tree.clone()
        if result.kinds.length() == 0:
            let parents = [cur.clone(), other.clone()]
            let msg = "Merge branch '{name}'"
            let id = self.make_commit(result.tree, parents, msg)
            self.set_head_commit(id)
            say("Merge made by the 'three-way' strategy.")
            say("[{self.current_name()} {short(id)}] {msg}")
            return
        self.merging = true
        self.merge_other = other.clone()
        self.merge_branch = name.clone()
        self.conflicts = result.kinds.clone()
        for k in result.kinds.keys().sorted():
            let kind = result.kinds.get_or(k, "")
            if kind == "modify/delete":
                say("CONFLICT (modify/delete): {k}")
            else:
                say("CONFLICT ({kind}): Merge conflict in {k}")
        say("Automatic merge failed; fix conflicts and then commit the result.")

    fn three_way(base: String, cur: String, other: String, branch: String) MergeResult:
        let btree = self.commit_tree(base)
        let otree = self.commit_tree(cur)
        let ttree = self.commit_tree(other)
        var tree = Map[String, String]()
        var overrides = Map[String, String]()
        var kinds = Map[String, String]()
        var all_names = union_names(btree, otree)
        for n in ttree.keys():
            if not btree.contains(n) and not otree.contains(n):
                all_names.append(n)
        all_names.sort()
        for name in all_names:
            if entry_eq(otree, ttree, name):
                if otree.contains(name):
                    tree[name.clone()] = otree.get_or(name, "")
            else if entry_eq(otree, btree, name):
                if ttree.contains(name):
                    tree[name.clone()] = ttree.get_or(name, "")
            else if entry_eq(ttree, btree, name):
                if otree.contains(name):
                    tree[name.clone()] = otree.get_or(name, "")
            else if otree.contains(name) != ttree.contains(name):
                kinds[name.clone()] = "modify/delete"
                if otree.contains(name):
                    tree[name.clone()] = otree.get_or(name, "")
                    overrides[name.clone()] = otree.get_or(name, "")
                else:
                    overrides[name.clone()] = ttree.get_or(name, "")
            else:
                var base_lines = List[String]()
                if btree.contains(name):
                    base_lines = split_lines(btree.get_or(name, ""))
                let ours = split_lines(otree.get_or(name, ""))
                let theirs = split_lines(ttree.get_or(name, ""))
                let merged = merge_lines(base_lines, ours, theirs, branch)
                if merged.clean:
                    tree[name.clone()] = merged.text.clone()
                else:
                    tree[name.clone()] = otree.get_or(name, "")
                    overrides[name.clone()] = merged.text.clone()
                    if btree.contains(name):
                        kinds[name.clone()] = "content"
                    else:
                        kinds[name.clone()] = "add/add"
        return MergeResult(tree: tree, overrides: overrides, kinds: kinds)

    var fn cmd_commit(message: String) Unit:
        if message == "":
            err("empty commit message")
            return
        if self.conflicts.length() > 0:
            var names = self.conflicts.keys().sorted()
            var listed = ""
            var first = true
            for n in names:
                if first:
                    listed = n.clone()
                    first = false
                else:
                    listed = "{listed} {n}"
            err("unresolved conflicts: {listed}")
            return
        if self.merging:
            let parents = [self.head_commit(), self.merge_other.clone()]
            let id = self.make_commit(self.index.clone(), parents, message)
            self.set_head_commit(id)
            self.merging = false
            self.merge_other = ""
            self.merge_branch = ""
            self.conflicts = Map[String, String]()
            say("[{self.current_name()} {short(id)}] {message}")
            return
        if tree_eq(self.index, self.head_tree()):
            say("nothing to commit")
            return
        var parents = List[String]()
        let head = self.head_commit()
        if head != "":
            parents.append(head.clone())
        let root = parents.length() == 0
        let id = self.make_commit(self.index.clone(), parents, message)
        self.set_head_commit(id)
        if root:
            say("[{self.current_name()} (root-commit) {short(id)}] {message}")
        else:
            say("[{self.current_name()} {short(id)}] {message}")

    // Dispatches a command word with its arguments; returns false for unknown words.
    var fn dispatch(cmd: String, args: List[String], line: String) Bool:
        if cmd == "rm":
            self.cmd_rm(args)
        else if cmd == "mv":
            self.cmd_mv(args)
        else if cmd == "cat":
            self.cmd_cat(args)
        else if cmd == "ls":
            self.cmd_ls()
        else if cmd == "add":
            self.cmd_add(args)
        else if cmd == "status":
            self.cmd_status()
        else if cmd == "diff":
            self.cmd_diff(args)
        else if cmd == "log":
            self.cmd_log(args)
        else if cmd == "branch":
            self.cmd_branch(args)
        else if cmd == "tag":
            self.cmd_tag(args)
        else if cmd == "show":
            self.cmd_show(args)
        else if cmd == "checkout":
            self.cmd_checkout(args)
        else if cmd == "reset":
            self.cmd_reset(args)
        else if cmd == "merge":
            self.cmd_merge(args)
        else:
            return false
        return true

fn if_default_head(args: List[String]) String:
    if args.length() == 2:
        return args[1].clone()
    return "HEAD"

export fn main() Int:
    let data = read_all(stdin()).get()
    let text = data.decode_utf8().get("")
    let lines = split_lines(text)
    var repo = Repo(files: Map[String, String](), index: Map[String, String](), commits: Map[String, Commit](), branches: Map[String, String](), tags: Map[String, String](), head_branch: "main", head_id: "", seq_count: 0, merging: false, merge_other: "", merge_branch: "", conflicts: Map[String, String]())
    repo.branches["main"] = ""
    var pos = 0
    while pos < lines.length():
        let raw = lines[pos].clone()
        pos += 1
        let line = raw.trim_end()
        let trimmed = line.trim_start()
        if trimmed == "" or trimmed.starts_with("#"):
            continue
        say("> {line}")
        let ws = words(line)
        let cmd = ws[0].clone()
        let args = tail(ws)
        if cmd == "write" or cmd == "append":
            if args.length() != 1:
                err("usage: {cmd} FILE")
                continue
            var content = ""
            while pos < lines.length() and lines[pos] != ".":
                content = "{content}{lines[pos]}\n"
                pos += 1
            if pos < lines.length():
                pos += 1
            repo.write_file(args[0], content, cmd == "append")
        else if cmd == "commit":
            let message = rest_after_word(line).trim()
            repo.cmd_commit(message)
        else:
            if not repo.dispatch(cmd, args, line):
                err("unknown command '{cmd}'")
    return 0
