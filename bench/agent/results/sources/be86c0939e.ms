import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import bit_and, bit_xor, shift_right, wrapping_multiply from "@std/math.ms"

let FNV_OFFSET = -3750763034362895579
let FNV_PRIME = 1099511628211
let LOW32 = 4294967295
let HEX = "0123456789abcdef"
let NAME_START = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/"
let NAME_REST = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-"

type Commit:
    id: String
    tree: Map[String, String]
    parents: List[String]
    message: String
    number: Int

type Resolution:
    id: String
    error: String

type Merged:
    text: String
    clean: Bool

type Repo:
    wt: Map[String, String]
    index: Map[String, String]
    conflicts: Set[String]
    commits: Map[String, Commit]
    order: List[String]
    branches: Map[String, String]
    tags: Map[String, String]
    head_name: String
    detached_id: String
    merging: Bool
    merge_other: String
    merge_branch: String

fn say(text: String) Unit:
    stdout().write("{text}\n").get()

fn say_raw(text: String) Unit:
    stdout().write(text).get()

fn fail(message: String) Resolution:
    return Resolution(id: "", error: message)

fn found(id: String) Resolution:
    return Resolution(id: id, error: "")

fn hex16(h: Int) String:
    let hi = bit_and(shift_right(h, 32), LOW32).to_string_radix(16).pad_start(8, "0")
    let lo = bit_and(h, LOW32).to_string_radix(16).pad_start(8, "0")
    return "{hi}{lo}"

fn fnv(text: String) String:
    let bytes = text.to_bytes()
    var h = FNV_OFFSET

    for i in 0..bytes.length():
        h = bit_xor(h, bytes.get(i).to_int())
        h = wrapping_multiply(h, FNV_PRIME)

    return hex16(h)

fn tree_hash(tree: Map[String, String]) String:
    var names = tree.keys()
    names.sort()

    var text = ""
    for n in names:
        text = "{text}{n} {fnv(tree.get(n).get())}\n"
    return fnv(text)

fn commit_id(tree: String, parents: List[String], message: String) String:
    var text = "tree {tree}\n"
    for p in parents:
        text = "{text}parent {p}\n"
    return fnv("{text}\n{message}\n")

fn short(id: String) String:
    return id.slice(0, 7).get()

fn body(tree: Map[String, String], name: String) String:
    if tree.contains(name):
        return tree.get(name).get()

    return ""

fn same_tree(a: Map[String, String], b: Map[String, String]) Bool:
    if a.keys().length() != b.keys().length():
        return false

    for n in a.keys():
        if not b.contains(n):
            return false
        if a.get(n).get() != b.get(n).get():
            return false

    return true

fn tokens(line: String) List[String]:
    var out = List[String]()
    for piece in line.split(" "):
        if piece != "":
            out.append(piece)
    return out

fn tail(args: List[String]) List[String]:
    var out = List[String]()
    for k in 1..args.length():
        out.append(args[k].clone())
    return out

fn message_after(line: String) String:
    let t = line.trim()
    let cs = t.chars()
    var k = 0
    while k < cs.length() and cs[k] != " ":
        k += 1
    return t.slice(k, t.length()).get().trim()

fn valid_name(name: String) Bool:
    if name == "":
        return false

    let cs = name.chars()

    for k in 0..cs.length():
        if k == 0 and not NAME_START.contains(cs[k]):
            return false
        if not NAME_REST.contains(cs[k]):
            return false

    return true

fn is_nat(s: String) Bool:
    if let v = s.parse_int():
        return v >= 0

    return false

fn is_hex_prefix(s: String) Bool:
    if s.length() < 4:
        return false

    for c in s.chars():
        if not HEX.contains(c):
            return false
    return true

fn lines_of(content: String) List[String]:
    var out = List[String]()
    if content == "":
        return out

    var parts = content.split("\n")
    parts.remove(-1)
    return parts

fn join_lines(lines: List[String]) String:
    var out = ""
    for l in lines:
        out = "{out}{l}\n"
    return out

fn sub_lines(lines: List[String], lo: Int, hi: Int) List[String]:
    var out = List[String]()
    for k in lo..hi:
        out.append(lines[k].clone())
    return out

fn lcs_table(a: List[String], b: List[String]) List[Int]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var t = List[Int]()
    for k in 0..(n + 1) * w:
        t.append(0)

    var i = n - 1

    while i >= 0:
        var j = m - 1

        while j >= 0:
            if a[i] == b[j]:
                t[i * w + j] = t[(i + 1) * w + j + 1] + 1
            else if t[(i + 1) * w + j] >= t[i * w + j + 1]:
                t[i * w + j] = t[(i + 1) * w + j]
            else:
                t[i * w + j] = t[i * w + j + 1]

            j -= 1

        i -= 1

    return t

# For each index of a, the index of its matching line in b, or -1.
fn match_pairs(a: List[String], b: List[String]) List[Int]:
    let t = lcs_table(a, b)
    let w = b.length() + 1
    var out = List[Int]()
    for k in 0..a.length():
        out.append(-1)

    var x = 0
    var y = 0

    while x < a.length() and y < b.length():
        if a[x] == b[y]:
            out[x] = y
            x += 1
            y += 1
        else if t[(x + 1) * w + y] >= t[x * w + y + 1]:
            x += 1
        else:
            y += 1

    return out

fn diff_lines(a: List[String], b: List[String]) List[String]:
    let m = match_pairs(a, b)
    var out = List[String]()
    var px = 0
    var py = 0

    for x in 0..a.length():
        if m[x] >= 0:
            let y = m[x]
            for k in px..x:
                out.append("- {a[k]}")
            for k in py..y:
                out.append("+ {b[k]}")
            out.append("  {a[x]}")
            px = x + 1
            py = y + 1

    for k in px..a.length():
        out.append("- {a[k]}")
    for k in py..b.length():
        out.append("+ {b[k]}")
    return out

fn emit_chunk(
    var out: List[String], base: List[String], ours: List[String], theirs: List[String],
    branch: String
) Bool:
    if ours == base:
        for l in theirs:
            out.append(l.clone())
        return true

    if theirs == base:
        for l in ours:
            out.append(l.clone())
        return true

    if ours == theirs:
        for l in ours:
            out.append(l.clone())
        return true

    out.append("<<<<<<< HEAD")
    for l in ours:
        out.append(l.clone())
    out.append("=======")
    for l in theirs:
        out.append(l.clone())
    out.append(">>>>>>> {branch}")
    return false

fn three_way(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Merged:
    let mb = match_pairs(base, ours)
    let mt = match_pairs(base, theirs)
    var out = List[String]()
    var clean = true
    var pb = 0
    var po = 0
    var pt = 0

    for k in 0..base.length():
        if mb[k] >= 0 and mt[k] >= 0:
            let ob = mb[k]
            let tb = mt[k]
            let ok = emit_chunk(
                var out, sub_lines(base, pb, k), sub_lines(ours, po, ob),
                sub_lines(theirs, pt, tb), branch
            )
            if not ok:
                clean = false
            out.append(base[k].clone())
            pb = k + 1
            po = ob + 1
            pt = tb + 1

    let ok = emit_chunk(
        var out, sub_lines(base, pb, base.length()), sub_lines(ours, po, ours.length()),
        sub_lines(theirs, pt, theirs.length()), branch
    )
    if not ok:
        clean = false
    return Merged(text: join_lines(out), clean: clean)

impl Repo:
    fn label() String:
        if self.head_name == "":
            return "detached"

        return self.head_name.clone()

    fn current() String:
        if self.head_name != "":
            return self.branches.get(self.head_name).get()

        return self.detached_id.clone()

    fn tree_of(id: String) Map[String, String]:
        if id == "":
            return Map[String, String]()

        return self.commits.get(id).get().tree.clone()

    fn head_tree() Map[String, String]:
        return self.tree_of(self.current())

    fn resolve_base(name: String, spec: String) Resolution:
        if name == "HEAD":
            let c = self.current()
            if c == "":
                return fail("unknown revision '{spec}'")

            return found(c)

        if self.branches.contains(name):
            let c = self.branches.get(name).get()
            if c != "":
                return found(c)

        if self.tags.contains(name):
            return found(self.tags.get(name).get())

        if is_hex_prefix(name):
            var hits = List[String]()
            for id in self.commits.keys():
                if id.starts_with(name):
                    hits.append(id)
            if hits.length() == 1:
                return found(hits[0].clone())
            if hits.length() > 1:
                return fail("ambiguous revision '{spec}'")

        return fail("unknown revision '{spec}'")

    fn resolve(spec: String) Resolution:
        let pieces = spec.split("~")
        if pieces.length() == 1:
            return self.resolve_base(spec, spec)
        if pieces.length() != 2 or not is_nat(pieces[1]):
            return fail("unknown revision '{spec}'")

        let steps = pieces[1].parse_int().get()
        let start = self.resolve_base(pieces[0], spec)
        if start.error != "":
            return start

        var id = start.id.clone()

        for step in 0..steps:
            let parents = self.commits.get(id).get().parents
            if parents.length() == 0:
                return fail("unknown revision '{spec}'")

            id = parents[0].clone()

        return found(id)

    fn ancestors(start: String) Set[String]:
        var seen = Set[String]()
        var stack = List[String]()
        stack.append(start.clone())

        while stack.length() > 0:
            let id = stack[stack.length() - 1].clone()
            stack.remove(-1)
            if seen.contains(id):
                continue

            for p in self.commits.get(id).get().parents:
                stack.append(p.clone())
            seen.add(id)

        return seen

    fn merge_base(a: String, b: String) String:
        let anc_a = self.ancestors(a)
        let anc_b = self.ancestors(b)
        var k = self.order.length() - 1

        while k >= 0:
            let id = self.order[k]
            if anc_a.contains(id) and anc_b.contains(id):
                return id.clone()

            k -= 1

        return ""

    var fn store(
        tree: Map[String, String],
        parents: List[String],
        message: String
    ) String:
        let id = commit_id(tree_hash(tree), parents, message)

        if not self.commits.contains(id):
            self.order.append(id.clone())

            let number = self.order.length()
            self.commits[id.clone()] = Commit(
                id: id.clone(), tree: tree, parents: parents, message: message,
                number: number
            )

        return id

    var fn move_head(id: String) Unit:
        if self.head_name != "":
            self.branches[self.head_name.clone()] = id.clone()
        else:
            self.detached_id = id.clone()

    fn banner(root: Bool, id: String, message: String) Unit:
        let where = self.label()

        if root:
            say("[{where} (root-commit) {short(id)}] {message}")
        else:
            say("[{where} {short(id)}] {message}")

    fn is_dirty() Bool:
        if not same_tree(self.index, self.head_tree()):
            return true

        for n in self.index.keys():
            if not self.wt.contains(n):
                return true
            if self.wt.get(n).get() != self.index.get(n).get():
                return true

        return false

    fn dirty_error() String:
        if self.is_dirty():
            return "local changes would be overwritten"

        return ""

    fn untracked_error(names: List[String]) String:
        var sorted_names = names.clone()
        sorted_names.sort()
        for n in sorted_names:
            if not self.index.contains(n) and self.wt.contains(n):
                return "untracked file would be overwritten: {n}"
        return ""

    fn switch_error(target: Map[String, String]) String:
        let d = self.dirty_error()
        if d != "":
            return d

        return self.untracked_error(target.keys())

    # Deletes the old index's files, then writes the target tree.
    var fn switch_to(tree: Map[String, String]) Unit:
        for n in self.index.keys():
            self.wt.remove(n)
        self.index = tree.clone()
        for n in tree.keys():
            self.wt[n.clone()] = tree.get(n).get()

    var fn reset_to(id: String) Unit:
        var names = self.index.keys()
        for n in self.head_tree().keys():
            names.append(n)
        for n in names:
            self.wt.remove(n)

        let tree = self.tree_of(id)
        self.move_head(id)
        self.index = tree.clone()
        for n in tree.keys():
            self.wt[n.clone()] = tree.get(n).get()
        self.conflicts = Set[String]()
        self.merging = false
        self.merge_other = ""
        self.merge_branch = ""

    var fn stage(name: String) Unit:
        if self.wt.contains(name):
            self.index[name.clone()] = self.wt.get(name).get()
        else:
            self.index.remove(name.clone())

        self.conflicts.remove(name)

    fn branch_error(name: String) String:
        if not valid_name(name):
            return "invalid branch name '{name}'"
        if self.branches.contains(name):
            return "branch '{name}' already exists"
        if self.current() == "":
            return "no commits yet"

        return ""

    # ---- commands ----

    var fn cmd_rm(names: List[String]) String:
        if names.length() == 0:
            return "usage: rm FILE..."

        for n in names:
            if not self.wt.contains(n):
                return "no such file: {n}"

            self.wt.remove(n)

        return ""

    var fn cmd_mv(args: List[String]) String:
        if args.length() != 2:
            return "usage: mv OLD NEW"
        if not self.wt.contains(args[0]):
            return "no such file: {args[0]}"

        let content = self.wt.get(args[0]).get()
        self.wt.remove(args[0].clone())
        self.wt[args[1].clone()] = content
        return ""

    fn cmd_cat(args: List[String]) String:
        if args.length() != 1:
            return "usage: cat FILE"
        if not self.wt.contains(args[0]):
            return "no such file: {args[0]}"

        say_raw(self.wt.get(args[0]).get())
        return ""

    fn cmd_ls() String:
        var names = self.wt.keys()
        names.sort()
        if names.length() == 0:
            say("(empty)")
        for n in names:
            say(n)
        return ""

    var fn cmd_add(paths: List[String]) String:
        if paths.length() == 0:
            return "usage: add PATH..."

        for p in paths:
            if p == ".":
                var all = Set[String]()
                for n in self.wt.keys():
                    all.add(n)
                for n in self.index.keys():
                    all.add(n)
                for n in self.conflicts.values():
                    all.add(n)
                for n in all.values():
                    self.stage(n)
            else:
                let known = (
                    self.wt.contains(p)
                    or self.index.contains(p)
                    or self.conflicts.contains(p)
                )
                if not known:
                    return "pathspec '{p}' did not match any files"

                self.stage(p)

        return ""

    fn cmd_status() String:
        if self.head_name != "":
            say("On branch {self.head_name}")
        else:
            say("HEAD detached at {short(self.detached_id)}")

        if self.merging:
            say("merging: {self.merge_branch}")

        let head = self.head_tree()
        var all = Set[String]()
        for n in head.keys():
            all.add(n)
        for n in self.index.keys():
            all.add(n)

        var names = all.values()
        names.sort()

        var staged = List[String]()

        for n in names:
            if self.conflicts.contains(n):
                continue

            let in_head = head.contains(n)
            let in_index = self.index.contains(n)

            if not in_head:
                staged.append("new file: {n}")
            else if not in_index:
                staged.append("deleted: {n}")
            else if head.get(n).get() != self.index.get(n).get():
                staged.append("modified: {n}")

        var unstaged = List[String]()
        var index_names = self.index.keys()
        index_names.sort()

        for n in index_names:
            if self.conflicts.contains(n):
                continue

            if not self.wt.contains(n):
                unstaged.append("deleted: {n}")
            else if self.wt.get(n).get() != self.index.get(n).get():
                unstaged.append("modified: {n}")

        var conflicted = self.conflicts.values()
        conflicted.sort()

        var unmerged = List[String]()
        for n in conflicted:
            unmerged.append("unmerged: {n}")

        var wt_names = self.wt.keys()
        wt_names.sort()

        var untracked = List[String]()
        for n in wt_names:
            if not self.index.contains(n) and not self.conflicts.contains(n):
                untracked.append(n.clone())

        if (
            staged.length() + unstaged.length() + unmerged.length() + untracked.length() == 0
        ):
            say("nothing to commit, working tree clean")
            return ""

        if staged.length() > 0:
            say("staged:")
            for l in staged:
                say("  {l}")

        if unstaged.length() > 0:
            say("unstaged:")
            for l in unstaged:
                say("  {l}")

        if unmerged.length() > 0:
            say("conflicts:")
            for l in unmerged:
                say("  {l}")

        if untracked.length() > 0:
            say("untracked:")
            for l in untracked:
                say("  {l}")

        return ""

    var fn cmd_commit(message: String) String:
        if message == "":
            return "empty commit message"

        if self.conflicts.length() > 0:
            var names = self.conflicts.values()
            names.sort()

            let joined = names.join(" ")
            return "unresolved conflicts: {joined}"

        let cur = self.current()

        if self.merging:
            var parents = List[String]()
            parents.append(cur.clone())
            parents.append(self.merge_other.clone())

            let tree = self.index.clone()
            let id = self.store(tree, parents, message.clone())
            self.move_head(id)
            self.merging = false
            self.merge_other = ""
            self.merge_branch = ""
            self.banner(false, id, message)
            return ""

        if same_tree(self.index, self.head_tree()):
            return "nothing to commit"

        var parents = List[String]()
        if cur != "":
            parents.append(cur.clone())

        let tree = self.index.clone()
        let id = self.store(tree, parents, message.clone())
        self.move_head(id)
        self.banner(cur == "", id, message)
        return ""

    fn cmd_log(args: List[String]) String:
        var limit = -1

        if args.length() == 0:
            limit = -1
        else if args.length() == 2 and args[0] == "-n" and is_nat(args[1]):
            limit = args[1].parse_int().get()
        else:
            return "usage: log [-n N]"

        let cur = self.current()
        if cur == "":
            return "no commits yet"

        let reach = self.ancestors(cur)
        var shown = 0
        var k = self.order.length() - 1

        while k >= 0:
            if limit >= 0 and shown >= limit:
                break

            let id = self.order[k]

            if reach.contains(id):
                let c = self.commits.get(id).get()

                if c.parents.length() == 2:
                    say(
                        "{short(id)} {c.message} (merge {short(c.parents[0])} {short(c.parents[1])})"
                    )
                else:
                    say("{short(id)} {c.message}")

                shown += 1

            k -= 1

        return ""

    fn cmd_diff(args: List[String]) String:
        if args.length() > 2:
            return "usage: diff [REF [REF]]"

        var left = Map[String, String]()
        var right = Map[String, String]()

        if args.length() == 0:
            left = self.index.clone()
            right = self.wt.clone()
        else if args.length() == 1:
            let r = self.resolve(args[0])
            if r.error != "":
                return r.error.clone()

            left = self.tree_of(r.id)
            right = self.wt.clone()
        else:
            let r1 = self.resolve(args[0])
            if r1.error != "":
                return r1.error.clone()

            let r2 = self.resolve(args[1])
            if r2.error != "":
                return r2.error.clone()

            left = self.tree_of(r1.id)
            right = self.tree_of(r2.id)

        var all = Set[String]()
        for n in left.keys():
            all.add(n)
        for n in right.keys():
            all.add(n)

        var names = all.values()
        names.sort()

        var any = false

        for n in names:
            let lp = left.contains(n)
            let rp = right.contains(n)
            let lc = body(left, n)
            let rc = body(right, n)
            if lp == rp and lc == rc:
                continue

            any = true
            say("diff {n}")

            if not lp:
                say("new file")
            else if not rp:
                say("deleted file")

            for line in diff_lines(lines_of(lc), lines_of(rc)):
                say(line)

        if not any:
            say("(no differences)")
        return ""

    var fn cmd_branch(args: List[String]) String:
        if args.length() == 0:
            if self.head_name == "":
                say("* (HEAD detached at {short(self.detached_id)})")

            var names = self.branches.keys()
            names.sort()

            for n in names:
                if n == self.head_name:
                    say("* {n}")
                else:
                    say("  {n}")

            return ""

        if args.length() == 1:
            let err = self.branch_error(args[0])
            if err != "":
                return err

            self.branches[args[0].clone()] = self.current()
            return ""

        if args.length() == 2 and args[0] == "-d":
            let name = args[1].clone()
            if not self.branches.contains(name):
                return "branch '{name}' not found"
            if name == self.head_name:
                return "cannot delete the current branch '{name}'"

            let c = self.branches.get(name).get()
            let cur = self.current()
            if c == "" or cur == "" or not self.ancestors(cur).contains(c):
                return "branch '{name}' is not fully merged"

            self.branches.remove(name.clone())
            say("Deleted branch {name} (was {short(c)}).")
            return ""

        return "usage: branch [NAME | -d NAME]"

    var fn cmd_tag(args: List[String]) String:
        if args.length() == 0:
            var names = self.tags.keys()
            names.sort()
            for n in names:
                say(n)
            return ""

        if args.length() > 2:
            return "usage: tag [NAME [REF]]"

        let name = args[0].clone()
        if not valid_name(name):
            return "invalid tag name '{name}'"
        if self.tags.contains(name):
            return "tag '{name}' already exists"

        let ref_text = if args.length() == 2: args[1].clone() else: "HEAD"

        if (args.length() == 1 or args[1] == "HEAD") and self.current() == "":
            return "no commits yet"

        let r = self.resolve(ref_text)
        if r.error != "":
            return r.error.clone()

        self.tags[name] = r.id.clone()
        return ""

    fn cmd_show(args: List[String]) String:
        if args.length() != 1:
            return "usage: show REF"

        let r = self.resolve(args[0])
        if r.error != "":
            return r.error.clone()

        let c = self.commits.get(r.id).get()
        say("commit {c.id}")
        say("tree {tree_hash(c.tree)}")
        for p in c.parents:
            say("parent {p}")
        say("message: {c.message}")
        say("files:")

        var names = c.tree.keys()
        names.sort()
        for n in names:
            say("  {n} {short(fnv(c.tree.get(n).get()))}")
        return ""

    var fn cmd_checkout(args: List[String]) String:
        if args.length() == 2 and args[0] == "-b":
            let name = args[1].clone()
            let err = self.branch_error(name)
            if err != "":
                return err

            let target = self.head_tree()
            let d = self.switch_error(target)
            if d != "":
                return d

            self.switch_to(target)
            self.branches[name.clone()] = self.current()
            self.head_name = name.clone()
            say("Switched to a new branch '{name}'")
            return ""

        if args.length() != 1:
            return "usage: checkout REF | checkout -b NAME"
        if self.merging:
            return "merge in progress"

        let name = args[0].clone()

        if self.branches.contains(name):
            if name == self.head_name:
                say("Already on '{name}'")
                return ""

            let target = self.tree_of(self.branches.get(name).get())
            let d = self.switch_error(target)
            if d != "":
                return d

            self.switch_to(target)
            self.head_name = name.clone()
            say("Switched to branch '{name}'")
            return ""

        let r = self.resolve(name)
        if r.error != "":
            return r.error.clone()

        let target = self.tree_of(r.id)
        let d = self.switch_error(target)
        if d != "":
            return d

        self.switch_to(target)
        self.head_name = ""
        self.detached_id = r.id.clone()

        let c = self.commits.get(r.id).get()
        say("HEAD is now at {short(r.id)} {c.message}")
        return ""

    var fn cmd_reset(args: List[String]) String:
        if args.length() == 0 or args[0] != "--hard" or args.length() > 2:
            return "usage: reset --hard [REF]"

        var target = ""

        if args.length() == 1:
            target = self.current()
            if target == "":
                return "no commits yet"
        else:
            let r = self.resolve(args[1])
            if r.error != "":
                return r.error.clone()

            target = r.id.clone()

        self.reset_to(target.clone())

        let c = self.commits.get(target).get()
        say("HEAD is now at {short(target)} {c.message}")
        return ""

    var fn cmd_merge(args: List[String]) String:
        if args.length() == 1 and args[0] == "--abort":
            if not self.merging:
                return "no merge in progress"

            self.reset_to(self.current())
            say("Merge aborted.")
            return ""

        if args.length() != 1:
            return "usage: merge BRANCH"
        if self.merging:
            return "merge in progress"

        let cur = self.current()
        if cur == "":
            return "no commits yet"

        let branch = args[0].clone()
        if not self.branches.contains(branch) or self.branches.get(branch).get() == "":
            return "unknown branch '{branch}'"

        let other = self.branches.get(branch).get()
        let d = self.dirty_error()
        if d != "":
            return d

        if self.ancestors(cur).contains(other):
            say("Already up to date.")
            return ""

        if self.ancestors(other).contains(cur):
            let target = self.tree_of(other)
            let e = self.untracked_error(target.keys())
            if e != "":
                return e

            self.switch_to(target)
            self.move_head(other)
            say("Fast-forward")
            return ""

        let base_tree = self.tree_of(self.merge_base(cur, other))
        let ours_tree = self.tree_of(cur)
        let theirs_tree = self.tree_of(other)
        var all = Set[String]()
        for n in base_tree.keys():
            all.add(n)
        for n in ours_tree.keys():
            all.add(n)
        for n in theirs_tree.keys():
            all.add(n)

        var names = all.values()
        names.sort()

        var result = Map[String, String]()
        var overrides = Map[String, String]()
        var kinds = Map[String, String]()

        for n in names:
            let bp = base_tree.contains(n)
            let bc = body(base_tree, n)
            let op = ours_tree.contains(n)
            let oc = body(ours_tree, n)
            let tp = theirs_tree.contains(n)
            let tc = body(theirs_tree, n)

            if op == tp and oc == tc:
                if op:
                    result[n.clone()] = oc
            else if op == bp and oc == bc:
                if tp:
                    result[n.clone()] = tc
            else if tp == bp and tc == bc:
                if op:
                    result[n.clone()] = oc
            else if op != tp:
                if op:
                    result[n.clone()] = oc.clone()
                    overrides[n.clone()] = oc
                else:
                    overrides[n.clone()] = tc

                kinds[n.clone()] = "modify/delete"
            else:
                let merged = three_way(lines_of(bc), lines_of(oc), lines_of(tc), branch)

                if merged.clean:
                    result[n.clone()] = merged.text.clone()
                else:
                    result[n.clone()] = oc.clone()
                    overrides[n.clone()] = merged.text.clone()

                    if bp:
                        kinds[n.clone()] = "content"
                    else:
                        kinds[n.clone()] = "add/add"

        var touched = result.keys()
        for n in overrides.keys():
            touched.append(n)

        let e = self.untracked_error(touched)
        if e != "":
            return e

        for n in self.index.keys():
            if not result.contains(n):
                self.wt.remove(n)
        for n in result.keys():
            self.wt[n.clone()] = result.get(n).get()
        for n in overrides.keys():
            self.wt[n.clone()] = overrides.get(n).get()
        self.index = result.clone()

        if kinds.keys().length() == 0:
            var parents = List[String]()
            parents.append(cur.clone())
            parents.append(other.clone())

            let message = "Merge branch '{branch}'"
            let id = self.store(result, parents, message.clone())
            self.move_head(id)
            say("Merge made by the 'three-way' strategy.")
            self.banner(false, id, message)
            return ""

        self.conflicts = Set[String]()
        for n in kinds.keys():
            self.conflicts.add(n)
        self.merging = true
        self.merge_other = other.clone()
        self.merge_branch = branch.clone()

        var conflicted = kinds.keys()
        conflicted.sort()

        for n in conflicted:
            let kind = kinds.get(n).get()

            if kind == "modify/delete":
                say("CONFLICT (modify/delete): {n}")
            else:
                say("CONFLICT ({kind}): Merge conflict in {n}")

        say("Automatic merge failed; fix conflicts and then commit the result.")
        return ""

fn new_repo() Repo:
    var branches = Map[String, String]()
    branches["main"] = ""
    return Repo(
        wt: Map[String, String](), index: Map[String, String](),
        conflicts: Set[String](), commits: Map[String, Commit](), order: List[String](),
        branches: branches, tags: Map[String, String](), head_name: "main",
        detached_id: "", merging: false, merge_other: "", merge_branch: ""
    )

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var repo = new_repo()
    var i = 0

    while i < lines.length():
        let line = lines[i].trim_end()
        i += 1
        if line.trim() == "" or line.trim_start().starts_with("#"):
            continue

        say("> {line}")

        let args = tokens(line)
        let cmd = args[0].clone()
        let rest = tail(args)
        var err = ""

        if cmd == "write" or cmd == "append":
            if rest.length() != 1:
                err = "usage: {cmd} FILE"
            else:
                var content = ""

                while i < lines.length() and lines[i] != ".":
                    content = "{content}{lines[i]}\n"
                    i += 1

                if i < lines.length():
                    i += 1

                if cmd == "write":
                    repo.wt[rest[0].clone()] = content
                else:
                    let prior = body(repo.wt, rest[0])
                    repo.wt[rest[0].clone()] = "{prior}{content}"
        else if cmd == "rm":
            err = repo.cmd_rm(rest)
        else if cmd == "mv":
            err = repo.cmd_mv(rest)
        else if cmd == "cat":
            err = repo.cmd_cat(rest)
        else if cmd == "ls":
            err = repo.cmd_ls()
        else if cmd == "add":
            err = repo.cmd_add(rest)
        else if cmd == "status":
            err = repo.cmd_status()
        else if cmd == "commit":
            err = repo.cmd_commit(message_after(line))
        else if cmd == "log":
            err = repo.cmd_log(rest)
        else if cmd == "diff":
            err = repo.cmd_diff(rest)
        else if cmd == "branch":
            err = repo.cmd_branch(rest)
        else if cmd == "tag":
            err = repo.cmd_tag(rest)
        else if cmd == "show":
            err = repo.cmd_show(rest)
        else if cmd == "checkout":
            err = repo.cmd_checkout(rest)
        else if cmd == "reset":
            err = repo.cmd_reset(rest)
        else if cmd == "merge":
            err = repo.cmd_merge(rest)
        else:
            err = "unknown command '{cmd}'"

        if err != "":
            say("error: {err}")

    return 0
