import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import bit_xor, bit_and, shift_right, wrapping_multiply from "@std/math.ms"

let ALNUM = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
let HEXCH = "0123456789abcdef"
let DIGITS = "0123456789"
let FIRSTCH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/"
let NAMECH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-"

type Commit:
    id: String
    parents: List[Int]
    message: String
    tree: Map[String, String]

type Merged:
    text: String
    clean: Bool

type Repo:
    files: Map[String, String]
    index: Map[String, String]
    clist: List[Commit]
    ids: Map[String, Int]
    branches: Map[String, Int]
    tags: Map[String, Int]
    head_branch: String
    head_seq: Int
    conflicts: Set[String]
    kinds: Map[String, String]
    merging: Bool
    merge_other: Int
    merge_branch: String

fn say(s: String) Unit:
    stdout().write("{s}\n").get()

fn fnv(text: String) Int:
    var h = -3750763034362895579

    for b in text.to_bytes().values():
        h = bit_xor(h, b.to_int())
        h = wrapping_multiply(h, 1099511628211)

    return h

fn hex16(h: Int) String:
    var s = ""
    var k = 15

    while k >= 0:
        let nib = bit_and(shift_right(h, k * 4), 15)
        s = s.concat(HEXCH.get(nib))
        k -= 1

    return s

fn tree_hash(tree: Map[String, String]) String:
    var text = ""

    for name in tree.keys().sorted():
        let h = hex16(fnv(tree.get_or(name, "")))
        text = text.concat("{name} {h}\n")

    return hex16(fnv(text))

fn commit_id(tree_h: String, parent_ids: List[String], message: String) String:
    var text = "tree {tree_h}\n"
    for p in parent_ids:
        text = text.concat("parent {p}\n")
    text = text.concat("\n{message}\n")
    return hex16(fnv(text))

fn lines_of(content: String) List[String]:
    var res = List[String]()
    if content.length() == 0:
        return res

    let parts = content.split("\n")
    let cnt = parts.length() - 1
    for i in 0..cnt:
        res.append(parts[i].clone())
    return res

fn content_of(lines: List[String]) String:
    var s = ""
    for l in lines:
        s = s.concat("{l}\n")
    return s

fn sub(lines: List[String], from: Int, to: Int) List[String]:
    var res = List[String]()
    var k = from

    while k < to:
        res.append(lines[k].clone())
        k += 1

    return res

fn all_in(s: String, allowed: String) Bool:
    for c in s.chars():
        if not allowed.contains(c):
            return false
    return true

fn valid_name(s: String) Bool:
    if s.length() == 0:
        return false
    if not FIRSTCH.contains(s.take(1)):
        return false

    return all_in(s.drop(1), NAMECH)

fn is_hex_prefix(s: String) Bool:
    return s.length() >= 4 and all_in(s, HEXCH)

fn maps_equal(a: Map[String, String], b: Map[String, String]) Bool:
    if a.length() != b.length():
        return false

    for name in a.keys():
        if not b.contains(name):
            return false
        if a.get_or(name, "") != b.get_or(name, ""):
            return false

    return true

fn tokenize(line: String) List[String]:
    var toks = List[String]()
    var cur = ""

    for c in line.chars():
        if c == " " or c == "\t":
            if cur.length() > 0:
                toks.append(cur.clone())
            cur = ""
        else:
            cur = cur.concat(c)

    if cur.length() > 0:
        toks.append(cur.clone())
    return toks

# Matching pairs of a against b (LCS walk). Result[i] = matched index in b, or -1.
fn match_map(a: List[String], b: List[String]) List[Int]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var table = List[Int]()
    for k in 0..(n + 1) * (m + 1):
        table.append(0)

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

    var res = List[Int]()
    for k in 0..n:
        res.append(-1)

    var x = 0
    var y = 0

    while x < n and y < m:
        if a[x] == b[y]:
            res[x] = y
            x += 1
            y += 1
        else if table[(x + 1) * w + y] >= table[x * w + y + 1]:
            x += 1
        else:
            y += 1

    return res

fn chunk_merge(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Merged:
    let bc = content_of(base)
    let oc = content_of(ours)
    let tc = content_of(theirs)
    if oc == bc:
        return Merged(text: tc, clean: true)
    if tc == bc:
        return Merged(text: oc, clean: true)
    if oc == tc:
        return Merged(text: oc, clean: true)

    let text = "<<<<<<< HEAD\n{oc}=======\n{tc}>>>>>>> {branch}\n"
    return Merged(text: text, clean: false)

fn merge_lines(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Merged:
    let bo = match_map(base, ours)
    let bt = match_map(base, theirs)
    var text = ""
    var clean = true
    var pb = 0
    var po = 0
    var pt = 0

    for s in 0..base.length():
        if bo[s] >= 0 and bt[s] >= 0:
            let so = bo[s]
            let st = bt[s]
            let mid = chunk_merge(
                sub(base, pb, s), sub(ours, po, so), sub(theirs, pt, st), branch
            )
            text = text.concat(mid.text)
            if not mid.clean:
                clean = false
            text = text.concat("{base[s]}\n")
            pb = s + 1
            po = so + 1
            pt = st + 1

    let last = chunk_merge(
        sub(base, pb, base.length()), sub(ours, po, ours.length()),
        sub(theirs, pt, theirs.length()), branch
    )
    text = text.concat(last.text)
    if not last.clean:
        clean = false
    return Merged(text: text, clean: clean)

# Prints a whole-file line diff of a (left) against b (right).
fn print_line_diff(a: List[String], b: List[String]) Unit:
    let mm = match_map(a, b)
    var pi = 0
    var pj = 0

    for x in 0..a.length():
        let y = mm[x]

        if y >= 0:
            for k in pi..x:
                say("- {a[k]}")
            for k in pj..y:
                say("+ {b[k]}")
            say("  {a[x]}")
            pi = x + 1
            pj = y + 1

    for k in pi..a.length():
        say("- {a[k]}")
    for k in pj..b.length():
        say("+ {b[k]}")

fn print_section(title: String, items: List[String]) Unit:
    if items.length() > 0:
        say(title)
        for it in items:
            say("  {it}")

impl Repo:
    fn cur_seq() Int:
        if self.head_branch.length() > 0:
            return self.branches.get_or(self.head_branch, 0)

        return self.head_seq

    fn label() String:
        if self.head_branch.length() > 0:
            return self.head_branch.clone()

        return "detached"

    fn tree_of(s: Int) Map[String, String]:
        if s == 0:
            return Map[String, String]()

        return self.clist[s - 1].tree.clone()

    fn short_of(s: Int) String:
        return self.clist[s - 1].id.take(7)

    fn msg_of(s: Int) String:
        return self.clist[s - 1].message.clone()

    fn id_of(s: Int) String:
        return self.clist[s - 1].id.clone()

    var fn move_head(s: Int) Unit:
        if self.head_branch.length() > 0:
            self.branches.add(self.head_branch.clone(), s)
        else:
            self.head_seq = s

    fn ancestors(s: Int) Set[Int]:
        var seen = Set[Int]()
        if s == 0:
            return seen

        var q = List[Int]()
        q.append(s)

        var qi = 0

        while qi < q.length():
            let c = q[qi]
            qi += 1

            if not seen.contains(c):
                seen.add(c)
                for p in self.clist[c - 1].parents:
                    q.append(p)

        return seen

    var fn make_commit(
        tree: Map[String, String],
        parents: List[Int],
        message: String
    ) Int:
        var pids = List[String]()
        for p in parents:
            pids.append(self.clist[p - 1].id.clone())

        let th = tree_hash(tree)
        let id = commit_id(th, pids, message)
        if self.ids.contains(id):
            return self.ids.get_or(id, 0)

        self.clist.append(
            Commit(
                id: id.clone(), parents: parents, message: message, tree: tree
            )
        )

        let s = self.clist.length()
        self.ids.add(id, s)
        return s

    # Returns the commit seq for REF, or 0 after printing an error.
    fn resolve(refname: String) Int:
        var base = refname.clone()
        var steps = 0

        if refname.contains("~"):
            let parts = refname.split("~")

            if (
                parts.length() != 2
                or not all_in(parts[1], DIGITS)
                or parts[1].length() == 0
            ):
                say("error: unknown revision '{refname}'")
                return 0

            base = parts[0].clone()

            if let n = parts[1].parse_int():
                steps = n
            else:
                say("error: unknown revision '{refname}'")
                return 0

        var s = 0

        if base == "HEAD":
            s = self.cur_seq()
        else if self.branches.contains(base):
            s = self.branches.get_or(base, 0)
        else if self.tags.contains(base):
            s = self.tags.get_or(base, 0)
        else if is_hex_prefix(base):
            var found = 0
            var count = 0

            for k in 0..self.clist.length():
                if self.clist[k].id.starts_with(base):
                    found = k + 1
                    count += 1

            if count > 1:
                say("error: ambiguous revision '{refname}'")
                return 0

            s = found

        if s == 0:
            say("error: unknown revision '{refname}'")
            return 0

        var k = 0

        while k < steps:
            if self.clist[s - 1].parents.length() == 0:
                say("error: unknown revision '{refname}'")
                return 0

            s = self.clist[s - 1].parents[0]
            k += 1

        return s

    fn dirty() Bool:
        let ht = self.tree_of(self.cur_seq())
        if not maps_equal(self.index, ht):
            return true

        for name in self.index.keys():
            if not self.files.contains(name):
                return true
            if self.files.get_or(name, "") != self.index.get_or(name, ""):
                return true

        return false

    # Prints the error and returns true when an untracked working file would be overwritten.
    fn untracked(names: List[String]) Bool:
        for name in names.sorted():
            if self.files.contains(name) and not self.index.contains(name):
                say("error: untracked file would be overwritten: {name}")
                return true

        return false

    # Sets index and working files to the target tree, as checkout does.
    var fn apply_tree(target: Map[String, String]) Unit:
        for name in self.index.keys():
            self.files.remove(name)
        for name in target.keys():
            self.files.add(name.clone(), target.get_or(name, ""))
        self.index = target

    var fn reset_to(s: Int) Unit:
        let old_head = self.tree_of(self.cur_seq())
        let target = self.tree_of(s)
        for name in self.index.keys():
            self.files.remove(name)
        for name in old_head.keys():
            self.files.remove(name)
        self.move_head(s)
        for name in target.keys():
            self.files.add(name.clone(), target.get_or(name, ""))
        self.index = target
        self.conflicts.clear()
        self.kinds.clear()
        self.merging = false
        self.merge_other = 0
        self.merge_branch = ""

    var fn cmd_rm(args: List[String]) Unit:
        if args.length() == 0:
            say("usage: rm FILE...")
            return

        for name in args:
            if not self.files.contains(name):
                say("error: no such file: {name}")
                return

            self.files.remove(name)

    var fn cmd_mv(args: List[String]) Unit:
        if args.length() != 2:
            say("usage: mv OLD NEW")
            return

        let old = args[0].clone()
        let nw = args[1].clone()

        if not self.files.contains(old):
            say("error: no such file: {old}")
            return

        if old == nw:
            return

        let content = self.files.get_or(old, "")
        self.files.remove(old)
        self.files.add(nw, content)

    fn cmd_cat(args: List[String]) Unit:
        if args.length() != 1:
            say("usage: cat FILE")
            return

        let name = args[0].clone()

        if not self.files.contains(name):
            say("error: no such file: {name}")
            return

        for l in lines_of(self.files.get_or(name, "")):
            say(l)

    fn cmd_ls() Unit:
        let names = self.files.keys().sorted()

        if names.length() == 0:
            say("(empty)")
            return

        for name in names:
            say(name)

    var fn cmd_add(args: List[String]) Unit:
        if args.length() == 0:
            say("usage: add PATH...")
            return

        for p in args:
            if p == ".":
                for name in self.files.keys():
                    self.index.add(name.clone(), self.files.get_or(name, ""))
                    if self.conflicts.contains(name):
                        self.conflicts.remove(name)

                for name in self.index.keys():
                    if not self.files.contains(name):
                        self.index.remove(name.clone())
                        if self.conflicts.contains(name):
                            self.conflicts.remove(name)
            else if self.files.contains(p):
                self.index.add(p.clone(), self.files.get_or(p, ""))
                if self.conflicts.contains(p):
                    self.conflicts.remove(p)
            else if self.index.contains(p):
                self.index.remove(p.clone())
                if self.conflicts.contains(p):
                    self.conflicts.remove(p)
            else if self.conflicts.contains(p):
                self.conflicts.remove(p)
            else:
                say("error: pathspec '{p}' did not match any files")
                return

    fn cmd_status() Unit:
        if self.head_branch.length() > 0:
            say("On branch {self.head_branch}")
        else:
            say("HEAD detached at {self.short_of(self.head_seq)}")

        if self.merging:
            say("merging: {self.merge_branch}")

        let ht = self.tree_of(self.cur_seq())
        var names = ht.keys()
        for k in self.index.keys():
            if not ht.contains(k):
                names.append(k)
        names = names.sorted()

        var staged = List[String]()

        for name in names:
            if self.conflicts.contains(name):
                continue

            let in_h = ht.contains(name)
            let in_i = self.index.contains(name)

            if in_i and not in_h:
                staged.append("new file: {name}")
            else if in_h and not in_i:
                staged.append("deleted: {name}")
            else if ht.get_or(name, "") != self.index.get_or(name, ""):
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
        for name in self.conflicts.values().sorted():
            unmerged.append("unmerged: {name}")

        var untracked = List[String]()
        for name in self.files.keys().sorted():
            if not self.index.contains(name) and not self.conflicts.contains(name):
                untracked.append(name)

        if (
            staged.length() + unstaged.length() + unmerged.length() + untracked.length() == 0
        ):
            say("nothing to commit, working tree clean")
            return

        print_section("staged:", staged)
        print_section("unstaged:", unstaged)
        print_section("conflicts:", unmerged)
        print_section("untracked:", untracked)

    fn cmd_diff(args: List[String]) Unit:
        if args.length() > 2:
            say("usage: diff [REF [REF]]")
            return

        var left = Map[String, String]()
        var right = Map[String, String]()

        if args.length() == 0:
            left = self.index.clone()
            right = self.files.clone()
        else if args.length() == 1:
            let s = self.resolve(args[0])
            if s == 0:
                return

            left = self.tree_of(s)
            right = self.files.clone()
        else:
            let s1 = self.resolve(args[0])
            if s1 == 0:
                return

            let s2 = self.resolve(args[1])
            if s2 == 0:
                return

            left = self.tree_of(s1)
            right = self.tree_of(s2)

        var names = left.keys()
        for k in right.keys():
            if not left.contains(k):
                names.append(k)
        names = names.sorted()

        var any = false

        for name in names:
            let lp = left.contains(name)
            let rp = right.contains(name)
            let lv = left.get_or(name, "")
            let rv = right.get_or(name, "")
            if lp == rp and lv == rv:
                continue

            any = true
            say("diff {name}")
            if not lp:
                say("new file")
            if not rp:
                say("deleted file")
            print_line_diff(lines_of(lv), lines_of(rv))

        if not any:
            say("(no differences)")

    fn cmd_log(args: List[String]) Unit:
        var limit = -1

        if (
            args.length() == 2
            and args[0] == "-n"
            and all_in(args[1], DIGITS)
            and args[1].length() > 0
        ):
            if let n = args[1].parse_int():
                limit = n
            else:
                say("usage: log [-n N]")
                return
        else if args.length() != 0:
            say("usage: log [-n N]")
            return

        let cur = self.cur_seq()

        if cur == 0:
            say("error: no commits yet")
            return

        var seqs = self.ancestors(cur).values()
        seqs.sort()

        var printed = 0
        var k = seqs.length() - 1

        while k >= 0 and (limit < 0 or printed < limit):
            let s = seqs[k]
            let c = self.clist[s - 1].parents.length()
            var line = "{self.short_of(s)} {self.msg_of(s)}"

            if c == 2:
                let p1 = self.short_of(self.clist[s - 1].parents[0])
                let p2 = self.short_of(self.clist[s - 1].parents[1])
                line = "{line} (merge {p1} {p2})"

            say(line)
            printed += 1
            k -= 1

    var fn cmd_branch(args: List[String]) Unit:
        if args.length() == 0:
            if self.head_branch.length() == 0:
                say("* (HEAD detached at {self.short_of(self.head_seq)})")

            for name in self.branches.keys().sorted():
                if self.head_branch == name:
                    say("* {name}")
                else:
                    say("  {name}")

            return

        if args.length() == 1:
            let name = args[0].clone()

            if not valid_name(name):
                say("error: invalid branch name '{name}'")
                return

            if self.branches.contains(name):
                say("error: branch '{name}' already exists")
                return

            let cur = self.cur_seq()

            if cur == 0:
                say("error: no commits yet")
                return

            self.branches.add(name, cur)
            return

        if args.length() == 2 and args[0] == "-d":
            let name = args[1].clone()

            if not self.branches.contains(name):
                say("error: branch '{name}' not found")
                return

            if self.head_branch == name:
                say("error: cannot delete the current branch '{name}'")
                return

            let bs = self.branches.get_or(name, 0)
            let anc = self.ancestors(self.cur_seq())

            if bs == 0 or not anc.contains(bs):
                say("error: branch '{name}' is not fully merged")
                return

            say("Deleted branch {name} (was {self.short_of(bs)}).")
            self.branches.remove(name)
            return

        say("usage: branch [NAME | -d NAME]")

    var fn cmd_tag(args: List[String]) Unit:
        if args.length() == 0:
            for name in self.tags.keys().sorted():
                say(name)
            return

        if args.length() > 2:
            say("usage: tag [NAME [REF]]")
            return

        let name = args[0].clone()

        if not valid_name(name):
            say("error: invalid tag name '{name}'")
            return

        if self.tags.contains(name):
            say("error: tag '{name}' already exists")
            return

        var refname = "HEAD"
        if args.length() == 2:
            refname = args[1].clone()

        if refname == "HEAD" and self.cur_seq() == 0:
            say("error: no commits yet")
            return

        let s = self.resolve(refname)
        if s == 0:
            return

        self.tags.add(name, s)

    fn cmd_show(args: List[String]) Unit:
        if args.length() != 1:
            say("usage: show REF")
            return

        let s = self.resolve(args[0])
        if s == 0:
            return

        let c = self.clist[s - 1].clone()
        say("commit {c.id}")
        say("tree {tree_hash(c.tree)}")
        for p in c.parents:
            say("parent {self.id_of(p)}")
        say("message: {c.message}")
        say("files:")

        for name in c.tree.keys().sorted():
            let h = hex16(fnv(c.tree.get_or(name, "")))
            say("  {name} {h.take(7)}")

    var fn cmd_checkout(args: List[String]) Unit:
        if args.length() == 2 and args[0] == "-b":
            let name = args[1].clone()

            if not valid_name(name):
                say("error: invalid branch name '{name}'")
                return

            if self.branches.contains(name):
                say("error: branch '{name}' already exists")
                return

            let cur = self.cur_seq()

            if cur == 0:
                say("error: no commits yet")
                return

            self.branches.add(name.clone(), cur)
            self.head_branch = name.clone()
            say("Switched to a new branch '{name}'")
            return

        if args.length() != 1:
            say("usage: checkout REF | checkout -b NAME")
            return

        if self.merging:
            say("error: merge in progress")
            return

        let tgt = args[0].clone()

        if self.branches.contains(tgt):
            if self.head_branch == tgt:
                say("Already on '{tgt}'")
                return

            let tree = self.tree_of(self.branches.get_or(tgt, 0))

            if self.dirty():
                say("error: local changes would be overwritten")
                return

            if self.untracked(tree.keys()):
                return

            self.apply_tree(tree)
            self.head_branch = tgt.clone()
            say("Switched to branch '{tgt}'")
            return

        let s = self.resolve(tgt)
        if s == 0:
            return

        let tree = self.tree_of(s)

        if self.dirty():
            say("error: local changes would be overwritten")
            return

        if self.untracked(tree.keys()):
            return

        self.apply_tree(tree)
        self.head_branch = ""
        self.head_seq = s
        say("HEAD is now at {self.short_of(s)} {self.msg_of(s)}")

    var fn cmd_reset(args: List[String]) Unit:
        if args.length() == 0 or args[0] != "--hard" or args.length() > 2:
            say("usage: reset --hard [REF]")
            return

        var s = 0

        if args.length() == 1:
            s = self.cur_seq()

            if s == 0:
                say("error: no commits yet")
                return
        else:
            s = self.resolve(args[1])
            if s == 0:
                return

        self.reset_to(s)
        say("HEAD is now at {self.short_of(s)} {self.msg_of(s)}")

    var fn merge_core(name: String, other: Int) Unit:
        let cur = self.cur_seq()
        let anc_cur = self.ancestors(cur)

        if anc_cur.contains(other):
            say("Already up to date.")
            return

        let anc_other = self.ancestors(other)

        if anc_other.contains(cur):
            let target = self.tree_of(other)
            if self.untracked(target.keys()):
                return

            self.apply_tree(target)
            self.move_head(other)
            say("Fast-forward")
            return

        var best = 0
        for x in anc_cur.values():
            if anc_other.contains(x) and x > best:
                best = x

        let base = self.tree_of(best)
        let ours = self.tree_of(cur)
        let theirs = self.tree_of(other)
        var all = Set[String]()
        for k in base.keys():
            all.add(k)
        for k in ours.keys():
            all.add(k)
        for k in theirs.keys():
            all.add(k)

        var result = Map[String, String]()
        var work = Map[String, String]()
        var conflict_names = Set[String]()
        var kinds = Map[String, String]()

        for path in all.values().sorted():
            let bp = base.contains(path)
            let bv = base.get_or(path, "")
            let op = ours.contains(path)
            let ov = ours.get_or(path, "")
            let tp = theirs.contains(path)
            let tv = theirs.get_or(path, "")

            if op == tp and ov == tv:
                if op:
                    result.add(path.clone(), ov)
            else if op == bp and ov == bv:
                if tp:
                    result.add(path.clone(), tv)
            else if tp == bp and tv == bv:
                if op:
                    result.add(path.clone(), ov)
            else if op != tp:
                conflict_names.add(path.clone())
                kinds.add(path.clone(), "modify/delete")

                if op:
                    result.add(path.clone(), ov.clone())
                    work.add(path.clone(), ov)
                else:
                    work.add(path.clone(), tv)
            else:
                let mr = merge_lines(lines_of(bv), lines_of(ov), lines_of(tv), name)

                if mr.clean:
                    result.add(path.clone(), mr.text)
                else:
                    conflict_names.add(path.clone())

                    if bp:
                        kinds.add(path.clone(), "content")
                    else:
                        kinds.add(path.clone(), "add/add")

                    result.add(path.clone(), ov)
                    work.add(path.clone(), mr.text)

        let check = result.keys().concat(work.keys())
        if self.untracked(check):
            return

        for path in self.index.keys():
            if not result.contains(path):
                self.files.remove(path)
        for path in result.keys():
            self.files.add(path.clone(), result.get_or(path, ""))
        for path in work.keys():
            self.files.add(path.clone(), work.get_or(path, ""))
        self.index = result.clone()

        if conflict_names.is_empty():
            let s = self.make_commit(result, [cur, other], "Merge branch '{name}'")
            self.move_head(s)
            say("Merge made by the 'three-way' strategy.")
            say("[{self.label()} {self.short_of(s)}] Merge branch '{name}'")
            return

        self.merging = true
        self.merge_other = other
        self.merge_branch = name.clone()
        self.kinds = kinds.clone()
        self.conflicts = conflict_names.clone()

        for path in conflict_names.values().sorted():
            let kind = kinds.get_or(path, "")

            if kind == "modify/delete":
                say("CONFLICT (modify/delete): {path}")
            else:
                say("CONFLICT ({kind}): Merge conflict in {path}")

        say("Automatic merge failed; fix conflicts and then commit the result.")

    var fn cmd_merge(args: List[String]) Unit:
        if args.length() == 1 and args[0] == "--abort":
            if not self.merging:
                say("error: no merge in progress")
                return

            self.reset_to(self.cur_seq())
            say("Merge aborted.")
            return

        if args.length() != 1:
            say("usage: merge BRANCH")
            return

        if self.merging:
            say("error: merge in progress")
            return

        if self.cur_seq() == 0:
            say("error: no commits yet")
            return

        let name = args[0].clone()

        if not self.branches.contains(name) or self.branches.get_or(name, 0) == 0:
            say("error: unknown branch '{name}'")
            return

        if self.dirty():
            say("error: local changes would be overwritten")
            return

        self.merge_core(name, self.branches.get_or(name, 0))

    var fn cmd_commit(line: String) Unit:
        let msg = line.drop(6).trim()

        if msg.length() == 0:
            say("error: empty commit message")
            return

        if self.conflicts.length() > 0:
            say(
                "error: unresolved conflicts: {self.conflicts.values().sorted().join(" ")}"
            )
            return

        let cur = self.cur_seq()

        if self.merging:
            var parents = List[Int]()
            parents.append(cur)
            parents.append(self.merge_other)

            let s = self.make_commit(self.index.clone(), parents, msg.clone())
            self.merging = false
            self.merge_other = 0
            self.merge_branch = ""
            self.conflicts.clear()
            self.kinds.clear()
            self.move_head(s)
            say("[{self.label()} {self.short_of(s)}] {msg}")
            return

        if maps_equal(self.index, self.tree_of(cur)):
            say("error: nothing to commit")
            return

        var parents = List[Int]()
        if cur != 0:
            parents.append(cur)

        let s = self.make_commit(self.index.clone(), parents, msg.clone())
        self.move_head(s)

        if cur == 0:
            say("[{self.label()} (root-commit) {self.short_of(s)}] {msg}")
        else:
            say("[{self.label()} {self.short_of(s)}] {msg}")

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var repo = Repo(
        files: Map[String, String](), index: Map[String, String](),
        clist: List[Commit](), ids: Map[String, Int](), branches: Map[String, Int](),
        tags: Map[String, Int](), head_branch: "main", head_seq: 0,
        conflicts: Set[String](), kinds: Map[String, String](), merging: false,
        merge_other: 0, merge_branch: ""
    )
    repo.branches.add("main", 0)

    let n = lines.length()
    var i = 0

    while i < n:
        let raw = lines[i].clone()
        i += 1

        let line = raw.trim_end()
        let t = line.trim_start()
        if t.length() == 0 or t.starts_with("#"):
            continue

        say("> {line}")

        let toks = tokenize(t)
        let cmd = toks[0].clone()
        let args = toks.drop(1)

        if cmd == "write" or cmd == "append":
            if args.length() != 1:
                say("usage: {cmd} FILE")
                continue

            let name = args[0].clone()
            var body = ""

            while i < n and lines[i] != ".":
                let bl = lines[i].clone()
                body = body.concat("{bl}\n")
                i += 1

            if i < n:
                i += 1

            if cmd == "write":
                repo.files.add(name, body)
            else:
                let prev = repo.files.get_or(name, "")
                repo.files.add(name, prev.concat(body))
        else if cmd == "rm":
            repo.cmd_rm(args)
        else if cmd == "mv":
            repo.cmd_mv(args)
        else if cmd == "cat":
            repo.cmd_cat(args)
        else if cmd == "ls":
            repo.cmd_ls()
        else if cmd == "add":
            repo.cmd_add(args)
        else if cmd == "status":
            repo.cmd_status()
        else if cmd == "commit":
            repo.cmd_commit(t)
        else if cmd == "diff":
            repo.cmd_diff(args)
        else if cmd == "log":
            repo.cmd_log(args)
        else if cmd == "branch":
            repo.cmd_branch(args)
        else if cmd == "tag":
            repo.cmd_tag(args)
        else if cmd == "show":
            repo.cmd_show(args)
        else if cmd == "checkout":
            repo.cmd_checkout(args)
        else if cmd == "reset":
            repo.cmd_reset(args)
        else if cmd == "merge":
            repo.cmd_merge(args)
        else:
            say("error: unknown command '{cmd}'")

    stdout().flush().get()
    return 0
