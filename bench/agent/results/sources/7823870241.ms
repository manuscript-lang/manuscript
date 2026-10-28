import {stdout, stdin} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import {wrapping_multiply, bit_xor, bit_and, shift_right_unsigned} from "@std/math.ms"

type Commit:
    id: String
    parents: List[String]
    message: String
    tree: Map[String, String]
    number: Int

type Outcome:
    lines: List[String]
    clean: Bool

type Pairs:
    left: List[Int]
    right: List[Int]

type Repo:
    files: Map[String, String]
    index: Map[String, String]
    commits: Map[String, Commit]
    branches: Map[String, String]
    tags: Map[String, String]
    head_branch: String
    detached: Bool
    head_at: String
    merging: Bool
    merge_other: String
    merge_branch: String
    conflicts: Map[String, String]

fn say(text: String) Unit:
    stdout().write(text + "\n").get()

fn err(message: String) Unit:
    say("error: " + message)

fn hash_hex(text: String) String:
    var h = -3750763034362895579

    for b in text.to_bytes().values():
        h = bit_xor(h, b.to_int())
        h = wrapping_multiply(h, 1099511628211)

    var out = ""
    for i in 0..16:
        out = out + bit_and(shift_right_unsigned(h, 60 - 4 * i), 15).to_string_radix(16)
    return out

fn short(id: String) String:
    return id.take(7)

fn tree_hash(tree: Map[String, String]) String:
    var names = tree.keys()
    names.sort()

    var text = ""
    for name in names:
        text = text + name + " " + hash_hex(tree[name]) + "\n"
    return hash_hex(text)

fn commit_hash(tree: Map[String, String], parents: List[String], message: String) String:
    var text = "tree " + tree_hash(tree) + "\n"
    for p in parents:
        text = text + "parent " + p + "\n"
    return hash_hex(text + "\n" + message + "\n")

fn is_hex_prefix(text: String) Bool:
    if text.scalar_length() < 4:
        return false

    for i in 0..text.scalar_length():
        if not "0123456789abcdef".contains(text.get(i)):
            return false
    return true

fn valid_name(name: String) Bool:
    if name.scalar_length() == 0:
        return false

    for i in 0..name.scalar_length():
        let c = name.scalar_at(i)
        if c == 45 and i > 0:
            continue

        let ok = (
            (c >= 48 and c <= 57)
            or (c >= 65 and c <= 90)
            or (c >= 97 and c <= 122)
            or c == 46
            or c == 95
            or c == 47
        )
        if not ok:
            return false

    return true

fn split_words(text: String) List[String]:
    var out = List[String]()
    for w in text.split(" "):
        if w != "":
            out.append(w)
    return out

fn lines_of(content: String) List[String]:
    var out = List[String]()
    if content == "":
        return out

    let parts = content.split("\n")
    for i in 0..parts.length() - 1:
        out.append(parts[i].clone())
    return out

fn text_of(lines: List[String]) String:
    var text = ""
    for l in lines:
        text = text + l + "\n"
    return text

fn span(xs: List[String], start: Int, end: Int) List[String]:
    var out = List[String]()
    for i in start..end:
        out.append(xs[i].clone())
    return out

fn section(title: String, items: List[String]) Unit:
    if items.length() == 0:
        return

    say(title)
    for item in items:
        say("  " + item)

fn pairs(a: List[String], b: List[String]) Pairs:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var table = List[Int]()
    for k in 0..(n + 1) * w:
        table.append(0)

    for k in 0..n:
        let i = n - 1 - k

        for l in 0..m:
            let j = m - 1 - l

            if a[i] == b[j]:
                table[i * w + j] = 1 + table[(i + 1) * w + j + 1]
            else:
                let down = table[(i + 1) * w + j]
                let right = table[i * w + j + 1]

                if down >= right:
                    table[i * w + j] = down
                else:
                    table[i * w + j] = right

    var left = List[Int]()
    var right = List[Int]()
    var i = 0
    var j = 0

    while i < n and j < m:
        if a[i] == b[j]:
            left.append(i)
            right.append(j)
            i += 1
            j += 1
        else if table[(i + 1) * w + j] >= table[i * w + j + 1]:
            i += 1
        else:
            j += 1

    return Pairs(left: left, right: right)

fn line_diff(a: List[String], b: List[String]) List[String]:
    let p = pairs(a, b)
    var out = List[String]()
    var ai = 0
    var bj = 0

    for k in 0..p.left.length():
        let i = p.left[k]
        let j = p.right[k]
        for x in ai..i:
            out.append("- " + a[x])
        for y in bj..j:
            out.append("+ " + b[y])
        out.append("  " + a[i])
        ai = i + 1
        bj = j + 1

    for x in ai..a.length():
        out.append("- " + a[x])
    for y in bj..b.length():
        out.append("+ " + b[y])
    return out

fn resolve_chunk(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Outcome:
    if ours == base:
        return Outcome(lines: theirs, clean: true)
    if theirs == base:
        return Outcome(lines: ours, clean: true)
    if ours == theirs:
        return Outcome(lines: ours, clean: true)

    var out = List[String]()
    out.append("<<<<<<< HEAD")
    for l in ours:
        out.append(l)
    out.append("=======")
    for l in theirs:
        out.append(l)
    out.append(">>>>>>> " + branch)
    return Outcome(lines: out, clean: false)

fn merge_lines(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Outcome:
    let po = pairs(base, ours)
    let pt = pairs(base, theirs)
    let nb = base.length()
    var om = List[Int]()
    var tm = List[Int]()

    for k in 0..nb:
        om.append(-1)
        tm.append(-1)

    for k in 0..po.left.length():
        om[po.left[k]] = po.right[k]
    for k in 0..pt.left.length():
        tm[pt.left[k]] = pt.right[k]

    var out = List[String]()
    var clean = true
    var pb = 0
    var pou = 0
    var ptt = 0

    for b in 0..nb:
        if om[b] >= 0 and tm[b] >= 0:
            let chunk = resolve_chunk(
                span(base, pb, b), span(ours, pou, om[b]), span(theirs, ptt, tm[b]),
                branch
            )
            for l in chunk.lines:
                out.append(l.clone())
            clean = clean and chunk.clean
            out.append(base[b].clone())
            pb = b + 1
            pou = om[b] + 1
            ptt = tm[b] + 1

    let last = resolve_chunk(
        span(base, pb, nb), span(ours, pou, ours.length()),
        span(theirs, ptt, theirs.length()), branch
    )
    for l in last.lines:
        out.append(l.clone())
    clean = clean and last.clean
    return Outcome(lines: out, clean: clean)

fn new_repo() Repo:
    var branches = Map[String, String]()
    branches["main"] = ""
    return Repo(
        files: Map[String, String](), index: Map[String, String](),
        commits: Map[String, Commit](), branches: branches, tags: Map[String, String](),
        head_branch: "main", detached: false, head_at: "", merging: false,
        merge_other: "", merge_branch: "", conflicts: Map[String, String]()
    )

impl Repo:
    fn head_id() String:
        if self.detached:
            return self.head_at.clone()

        return self.branches.get_or(self.head_branch, "")

    fn label() String:
        if self.detached:
            return "detached"

        return self.head_branch.clone()

    fn tree_of(id: String) Map[String, String]:
        if id == "":
            return Map[String, String]()

        return self.commits.get(id).get().tree.clone()

    fn head_tree() Map[String, String]:
        return self.tree_of(self.head_id())

    fn closure(start: String) Map[String, Commit]:
        var found = Map[String, Commit]()
        var todo = List[String]()
        if start != "":
            todo.append(start)

        var k = 0

        while k < todo.length():
            let id = todo[k]
            k += 1

            if not found.contains(id):
                let c = self.commits.get(id).get()
                found[id.clone()] = c.clone()
                for p in c.parents:
                    todo.append(p.clone())

        return found

    fn merge_base(a: String, b: String) String:
        let other = self.closure(b)
        var best = ""
        var best_number = -1

        for c in self.closure(a).values():
            if other.contains(c.id) and c.number > best_number:
                best = c.id.clone()
                best_number = c.number

        return best

    fn same_tree(a: Map[String, String], b: Map[String, String]) Bool:
        if a.length() != b.length():
            return false

        for name in a.keys():
            if not b.contains(name) or b[name] != a[name]:
                return false
        return true

    fn dirty() Bool:
        if not self.same_tree(self.index, self.head_tree()):
            return true

        for name in self.index.keys():
            if not self.files.contains(name) or self.files[name] != self.index[name]:
                return true
        return false

    fn first_untracked(names: List[String]) String:
        var sorted = names.clone()
        sorted.sort()
        for name in sorted:
            if not self.index.contains(name) and self.files.contains(name):
                return name
        return ""

    var fn move_head(id: String) Unit:
        if self.detached:
            self.head_at = id
        else:
            self.branches[self.head_branch.clone()] = id

    var fn make_commit(
        tree: Map[String, String],
        parents: List[String],
        message: String
    ) String:
        let id = commit_hash(tree, parents, message)
        if not self.commits.contains(id):
            self.commits[id.clone()] = Commit(
                id: id.clone(), parents: parents, message: message, tree: tree,
                number: self.commits.length() + 1
            )
        return id

    var fn switch_to(tree: Map[String, String]) Unit:
        for name in self.index.keys():
            self.files.remove(name)
        for name in tree.keys():
            self.files[name.clone()] = tree[name].clone()
        self.index = tree.clone()

    var fn hard_reset(id: String) Unit:
        let old_tree = self.head_tree()
        for name in self.index.keys():
            self.files.remove(name)
        for name in old_tree.keys():
            self.files.remove(name)
        self.move_head(id.clone())

        let tree = self.tree_of(id)
        for name in tree.keys():
            self.files[name.clone()] = tree[name].clone()
        self.index = tree.clone()
        self.merging = false
        self.merge_other = ""
        self.merge_branch = ""
        self.conflicts.clear()

    fn resolve(spec: String) String:
        var base = spec.clone()
        var steps = 0

        if spec.contains("~"):
            let parts = spec.split("~", 2)
            base = parts[0].clone()

            if let n = parts[1].parse_int():
                if n < 0:
                    err("unknown revision '" + spec + "'")
                    return ""

                steps = n
            else:
                err("unknown revision '" + spec + "'")
                return ""

        var id = ""

        if base == "HEAD":
            id = self.head_id()
        else if self.branches.get_or(base, "") != "":
            id = self.branches.get_or(base, "")
        else if self.tags.contains(base):
            id = self.tags.get_or(base, "")
        else if is_hex_prefix(base):
            var matches = List[String]()
            for cid in self.commits.keys():
                if cid.starts_with(base):
                    matches.append(cid)

            if matches.length() > 1:
                err("ambiguous revision '" + spec + "'")
                return ""

            if matches.length() == 1:
                id = matches[0].clone()

        if id == "":
            err("unknown revision '" + spec + "'")
            return ""

        for s in 0..steps:
            let c = self.commits.get(id).get()

            if c.parents.length() == 0:
                err("unknown revision '" + spec + "'")
                return ""

            id = c.parents[0].clone()

        return id

    var fn cmd_write(name: String, body: List[String], extend: Bool) Unit:
        var text = ""
        if extend:
            text = self.files.get_or(name, "")
        self.files[name] = text + text_of(body)

    var fn cmd_rm(args: List[String]) Unit:
        if args.length() == 0:
            err("usage: rm FILE...")
            return

        for name in args:
            if not self.files.contains(name):
                err("no such file: " + name)
                return

            self.files.remove(name)

    var fn cmd_mv(args: List[String]) Unit:
        if args.length() != 2:
            err("usage: mv OLD NEW")
            return

        let old = args[0]
        let new = args[1]

        if not self.files.contains(old):
            err("no such file: " + old)
            return

        if old == new:
            return

        self.files[new.clone()] = self.files[old].clone()
        self.files.remove(old.clone())

    fn cmd_cat(args: List[String]) Unit:
        if args.length() != 1:
            err("usage: cat FILE")
            return

        if not self.files.contains(args[0]):
            err("no such file: " + args[0])
            return

        stdout().write(self.files[args[0]]).get()

    fn cmd_ls() Unit:
        var names = self.files.keys()

        if names.length() == 0:
            say("(empty)")
            return

        names.sort()
        for name in names:
            say(name)

    var fn cmd_add(args: List[String]) Unit:
        if args.length() == 0:
            err("usage: add PATH...")
            return

        for p in args:
            if p == ".":
                self.index = self.files.clone()
                self.conflicts.clear()
            else if self.files.contains(p):
                self.index[p.clone()] = self.files[p].clone()
                self.conflicts.remove(p)
            else if self.index.contains(p):
                self.index.remove(p.clone())
                self.conflicts.remove(p)
            else if self.conflicts.contains(p):
                self.conflicts.remove(p)
            else:
                err("pathspec '" + p + "' did not match any files")
                return

    fn cmd_status() Unit:
        let head = self.head_tree()

        if self.detached:
            say("HEAD detached at " + short(self.head_at))
        else:
            say("On branch " + self.head_branch)

        if self.merging:
            say("merging: " + self.merge_branch)

        var names = head.keys()
        for name in self.index.keys():
            if not head.contains(name):
                names.append(name)
        names.sort()

        var staged = List[String]()

        for name in names:
            if self.conflicts.contains(name):
                continue

            if self.index.contains(name) and not head.contains(name):
                staged.append("new file: " + name)
            else if head.contains(name) and not self.index.contains(name):
                staged.append("deleted: " + name)
            else if head.get_or(name, "") != self.index.get_or(name, ""):
                staged.append("modified: " + name)

        var index_names = self.index.keys()
        index_names.sort()

        var unstaged = List[String]()

        for name in index_names:
            if self.conflicts.contains(name):
                continue

            if not self.files.contains(name):
                unstaged.append("deleted: " + name)
            else if self.files[name] != self.index[name]:
                unstaged.append("modified: " + name)

        var conflicted = self.conflicts.keys()
        conflicted.sort()

        var unmerged = List[String]()
        for name in conflicted:
            unmerged.append("unmerged: " + name)

        var file_names = self.files.keys()
        file_names.sort()

        var untracked = List[String]()
        for name in file_names:
            if not self.index.contains(name) and not self.conflicts.contains(name):
                untracked.append(name)

        if (
            staged.length() + unstaged.length() + unmerged.length() + untracked.length() == 0
        ):
            say("nothing to commit, working tree clean")
            return

        section("staged:", staged)
        section("unstaged:", unstaged)
        section("conflicts:", unmerged)
        section("untracked:", untracked)

    var fn cmd_commit(message: String) Unit:
        if message == "":
            err("empty commit message")
            return

        var conflicted = self.conflicts.keys()
        conflicted.sort()

        if conflicted.length() > 0:
            err("unresolved conflicts: " + conflicted.join(" "))
            return

        let tree = self.index.clone()
        var id = ""
        var root = false

        if self.merging:
            id = self.make_commit(
                tree, [self.head_id(), self.merge_other.clone()], message.clone()
            )
        else:
            if self.same_tree(tree, self.head_tree()):
                err("nothing to commit")
                return

            var parents = List[String]()

            if self.head_id() == "":
                root = true
            else:
                parents.append(self.head_id())

            id = self.make_commit(tree, parents, message.clone())

        self.merging = false
        self.merge_other = ""
        self.merge_branch = ""
        self.move_head(id.clone())

        let root_label = if root: " (root-commit)" else: ""

        say("[" + self.label() + root_label + " " + short(id) + "] " + message)

    var fn cmd_log(args: List[String]) Unit:
        var limit = -1

        if args.length() == 2 and args[0] == "-n":
            if let n = args[1].parse_int():
                if n < 0:
                    err("usage: log [-n N]")
                    return

                limit = n
            else:
                err("usage: log [-n N]")
                return
        else if args.length() != 0:
            err("usage: log [-n N]")
            return

        if self.head_id() == "":
            err("no commits yet")
            return

        var commits = self.closure(self.head_id()).values()
        commits.sort(fn a, b: b.number.compare(a.number))

        var shown = 0

        for c in commits:
            if limit >= 0 and shown >= limit:
                break

            shown += 1

            var line = short(c.id) + " " + c.message
            if c.parents.length() == 2:
                line = (
                    line
                    + " (merge "
                    + short(c.parents[0])
                    + " "
                    + short(c.parents[1])
                    + ")"
                )
            say(line)

    var fn cmd_diff(args: List[String]) Unit:
        if args.length() > 2:
            err("usage: diff [REF [REF]]")
            return

        var left = self.index.clone()
        var right = self.files.clone()

        if args.length() == 1:
            let id = self.resolve(args[0].clone())
            if id == "":
                return

            left = self.tree_of(id)
        else if args.length() == 2:
            let first = self.resolve(args[0].clone())
            if first == "":
                return

            let second = self.resolve(args[1].clone())
            if second == "":
                return

            left = self.tree_of(first)
            right = self.tree_of(second)

        var names = left.keys()
        for name in right.keys():
            if not left.contains(name):
                names.append(name)
        names.sort()

        var changed = false

        for name in names:
            let in_left = left.contains(name)
            let in_right = right.contains(name)
            let left_text = left.get_or(name, "")
            let right_text = right.get_or(name, "")
            if in_left == in_right and left_text == right_text:
                continue

            changed = true
            say("diff " + name)
            if not in_left:
                say("new file")
            if not in_right:
                say("deleted file")
            for l in line_diff(lines_of(left_text), lines_of(right_text)):
                say(l)

        if not changed:
            say("(no differences)")

    var fn cmd_branch(args: List[String]) Unit:
        if args.length() == 0:
            if self.detached:
                say("* (HEAD detached at " + short(self.head_at) + ")")

            var names = self.branches.keys()
            names.sort()

            for name in names:
                if not self.detached and name == self.head_branch:
                    say("* " + name)
                else:
                    say("  " + name)

            return

        if args.length() == 1:
            let name = args[0]

            if not valid_name(name):
                err("invalid branch name '" + name + "'")
                return

            if self.branches.contains(name):
                err("branch '" + name + "' already exists")
                return

            if self.head_id() == "":
                err("no commits yet")
                return

            self.branches[name.clone()] = self.head_id()
            return

        if args.length() == 2 and args[0] == "-d":
            let name = args[1]

            if not self.branches.contains(name):
                err("branch '" + name + "' not found")
                return

            if not self.detached and self.head_branch == name:
                err("cannot delete the current branch '" + name + "'")
                return

            let target = self.branches.get_or(name, "")

            if target == "" or not self.closure(self.head_id()).contains(target):
                err("branch '" + name + "' is not fully merged")
                return

            self.branches.remove(name.clone())
            say("Deleted branch " + name + " (was " + short(target) + ").")
            return

        err("usage: branch [NAME | -d NAME]")

    var fn cmd_tag(args: List[String]) Unit:
        if args.length() == 0:
            var names = self.tags.keys()
            names.sort()
            for name in names:
                say(name)
            return

        if args.length() > 2:
            err("usage: tag [NAME [REF]]")
            return

        let name = args[0]

        if not valid_name(name):
            err("invalid tag name '" + name + "'")
            return

        if self.tags.contains(name):
            err("tag '" + name + "' already exists")
            return

        let spec = if args.length() == 2: args[1].clone() else: "HEAD"

        if spec == "HEAD" and self.head_id() == "":
            err("no commits yet")
            return

        let id = self.resolve(spec)
        if id == "":
            return

        self.tags[name.clone()] = id

    fn cmd_show(args: List[String]) Unit:
        if args.length() != 1:
            err("usage: show REF")
            return

        let id = self.resolve(args[0].clone())
        if id == "":
            return

        let c = self.commits.get(id).get()
        say("commit " + id)
        say("tree " + tree_hash(c.tree))
        for p in c.parents:
            say("parent " + p)
        say("message: " + c.message)
        say("files:")

        var names = c.tree.keys()
        names.sort()
        for name in names:
            say("  " + name + " " + short(hash_hex(c.tree[name])))

    var fn cmd_checkout(args: List[String]) Unit:
        if args.length() == 2 and args[0] == "-b":
            let name = args[1]

            if not valid_name(name):
                err("invalid branch name '" + name + "'")
                return

            if self.branches.contains(name):
                err("branch '" + name + "' already exists")
                return

            if self.head_id() == "":
                err("no commits yet")
                return

            let tree = self.head_tree()

            if self.dirty():
                err("local changes would be overwritten")
                return

            let untracked = self.first_untracked(tree.keys())

            if untracked != "":
                err("untracked file would be overwritten: " + untracked)
                return

            self.branches[name.clone()] = self.head_id()
            self.switch_to(tree)
            self.head_branch = name.clone()
            self.detached = false
            say("Switched to a new branch '" + name + "'")
            return

        if args.length() != 1:
            err("usage: checkout REF | checkout -b NAME")
            return

        if self.merging:
            err("merge in progress")
            return

        let target = args[0]

        if self.branches.contains(target):
            if not self.detached and self.head_branch == target:
                say("Already on '" + target + "'")
                return

            let tree = self.tree_of(self.branches.get_or(target, ""))

            if self.dirty():
                err("local changes would be overwritten")
                return

            let untracked = self.first_untracked(tree.keys())

            if untracked != "":
                err("untracked file would be overwritten: " + untracked)
                return

            self.switch_to(tree)
            self.head_branch = target.clone()
            self.detached = false
            say("Switched to branch '" + target + "'")
            return

        let id = self.resolve(target.clone())
        if id == "":
            return

        let tree = self.tree_of(id)

        if self.dirty():
            err("local changes would be overwritten")
            return

        let untracked = self.first_untracked(tree.keys())

        if untracked != "":
            err("untracked file would be overwritten: " + untracked)
            return

        self.switch_to(tree)
        self.detached = true
        self.head_at = id.clone()
        say("HEAD is now at " + short(id) + " " + self.commits.get(id).get().message)

    var fn cmd_reset(args: List[String]) Unit:
        if args.length() == 0 or args.length() > 2 or args[0] != "--hard":
            err("usage: reset --hard [REF]")
            return

        var id = self.head_id()

        if args.length() == 2:
            id = self.resolve(args[1].clone())
            if id == "":
                return
        else if id == "":
            err("no commits yet")
            return

        self.hard_reset(id.clone())
        say("HEAD is now at " + short(id) + " " + self.commits.get(id).get().message)

    var fn cmd_merge(args: List[String]) Unit:
        if args.length() == 1 and args[0] == "--abort":
            if not self.merging:
                err("no merge in progress")
                return

            self.hard_reset(self.head_id())
            say("Merge aborted.")
            return

        if args.length() != 1:
            err("usage: merge BRANCH")
            return

        if self.merging:
            err("merge in progress")
            return

        if self.head_id() == "":
            err("no commits yet")
            return

        let branch = args[0]

        if self.branches.get_or(branch, "") == "":
            err("unknown branch '" + branch + "'")
            return

        if self.dirty():
            err("local changes would be overwritten")
            return

        let cur = self.head_id()
        let other = self.branches.get_or(branch, "")

        if self.closure(cur.clone()).contains(other):
            say("Already up to date.")
            return

        if self.closure(other.clone()).contains(cur):
            let tree = self.tree_of(other)
            let untracked = self.first_untracked(tree.keys())

            if untracked != "":
                err("untracked file would be overwritten: " + untracked)
                return

            self.switch_to(tree)
            self.move_head(other)
            say("Fast-forward")
            return

        let base_id = self.merge_base(cur.clone(), other.clone())
        let base = self.tree_of(base_id)
        let ours = self.tree_of(cur)
        let theirs = self.tree_of(other)
        var names = base.keys()
        for name in ours.keys():
            if not base.contains(name):
                names.append(name)
        for name in theirs.keys():
            if not base.contains(name) and not ours.contains(name):
                names.append(name)
        names.sort()

        var result = Map[String, String]()
        var overrides = Map[String, String]()
        var kinds = Map[String, String]()

        for name in names:
            let in_base = base.contains(name)
            let in_ours = ours.contains(name)
            let in_theirs = theirs.contains(name)
            let b = base.get_or(name, "")
            let o = ours.get_or(name, "")
            let t = theirs.get_or(name, "")

            if in_ours == in_theirs and o == t:
                if in_ours:
                    result[name] = o
            else if in_ours == in_base and o == b:
                if in_theirs:
                    result[name] = t
            else if in_theirs == in_base and t == b:
                if in_ours:
                    result[name] = o
            else if in_ours != in_theirs:
                if in_ours:
                    result[name.clone()] = o.clone()
                    overrides[name.clone()] = o
                else:
                    overrides[name.clone()] = t

                kinds[name] = "modify/delete"
            else:
                let merged = merge_lines(lines_of(b), lines_of(o), lines_of(t), branch)

                if merged.clean:
                    result[name] = text_of(merged.lines)
                else:
                    result[name.clone()] = o
                    overrides[name.clone()] = text_of(merged.lines)

                    if in_base:
                        kinds[name] = "content"
                    else:
                        kinds[name] = "add/add"

        var touched = result.keys()
        for name in overrides.keys():
            if not result.contains(name):
                touched.append(name)

        let untracked = self.first_untracked(touched)

        if untracked != "":
            err("untracked file would be overwritten: " + untracked)
            return

        for name in self.index.keys():
            if not result.contains(name):
                self.files.remove(name)
        for name in result.keys():
            self.files[name.clone()] = result[name].clone()
        for name in overrides.keys():
            self.files[name.clone()] = overrides[name].clone()
        self.index = result.clone()

        if kinds.length() == 0:
            let id = self.make_commit(
                result.clone(), [cur, other], "Merge branch '" + branch + "'"
            )
            self.move_head(id.clone())
            say("Merge made by the 'three-way' strategy.")
            say(
                "[" + self.label() + " " + short(
                    id
                ) + "] Merge branch '" + branch + "'"
            )
            return

        self.merging = true
        self.merge_other = other
        self.merge_branch = branch.clone()
        self.conflicts = kinds.clone()

        var conflicted = kinds.keys()
        conflicted.sort()

        for name in conflicted:
            let kind = kinds[name]

            if kind == "modify/delete":
                say("CONFLICT (modify/delete): " + name)
            else:
                say("CONFLICT (" + kind + "): Merge conflict in " + name)

        say("Automatic merge failed; fix conflicts and then commit the result.")

    var fn run(cmd: String, args: List[String], rest: String) Unit:
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
        else if cmd == "commit":
            self.cmd_commit(rest)
        else if cmd == "log":
            self.cmd_log(args)
        else if cmd == "diff":
            self.cmd_diff(args)
        else if cmd == "branch":
            self.cmd_branch(args)
        else if cmd == "tag":
            self.cmd_tag(args)
        else if cmd == "show":
            self.cmd_show(args)
        else if cmd == "checkout":
            self.cmd_checkout(args)
        else if cmd == "merge":
            self.cmd_merge(args)
        else if cmd == "reset":
            self.cmd_reset(args)
        else:
            err("unknown command '" + cmd + "'")

export fn main() Int:
    var repo = new_repo()
    let lines = read_lines(stdin()).get()
    var pos = 0

    while pos < lines.length():
        let line = lines[pos].trim_end()
        pos += 1

        let text = line.trim()

        if not (text == "" or text.starts_with("#")):
            say("> " + line)

            let words = split_words(text)
            let cmd = words[0]
            var args = List[String]()
            for k in 1..words.length():
                args.append(words[k].clone())

            if cmd == "write" or cmd == "append":
                if args.length() != 1:
                    err("usage: " + cmd + " FILE")
                else:
                    var body = List[String]()

                    while pos < lines.length() and lines[pos] != ".":
                        body.append(lines[pos].clone())
                        pos += 1

                    pos += 1
                    repo.cmd_write(args[0].clone(), body, cmd == "append")
            else:
                let rest = text.split(cmd, 2) [1].trim()
                repo.run(cmd, args, rest)

    return 0
