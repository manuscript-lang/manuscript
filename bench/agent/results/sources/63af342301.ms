from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines
from "@std/math.ms" import bit_and, bit_xor, shift_right_unsigned, wrapping_multiply

let FNV_OFFSET = -3750763034362895579
let FNV_PRIME = 1099511628211
let HEX_DIGITS = "0123456789abcdef"
let NO_LIMIT = 9223372036854775807

type Commit:
    id: String
    tree: Map[String, String]
    parents: List[String]
    message: String
    number: Int

type Pair:
    a: Int
    b: Int

type Anchor:
    b: Int
    o: Int
    t: Int

type Found:
    id: String
    error: String

type Merged:
    lines: List[String]
    clean: Bool

type Repo:
    input: List[String]
    pos: Int
    out: List[String]
    commits: Map[String, Commit]
    branches: Map[String, String]
    tags: Map[String, String]
    work: Map[String, String]
    index: Map[String, String]
    conflicts: Set[String]
    head_branch: String
    detached: Bool
    detached_at: String
    merging: Bool
    merge_other: String
    merge_name: String
    next_number: Int

def fnv(text: String) -> Int:
    var h = FNV_OFFSET

    for b in text.to_bytes().values():
        h = bit_xor(h, b.to_int())
        h = wrapping_multiply(h, FNV_PRIME)

    return h

def hex16(h: Int) -> String:
    var s = ""
    for i in 0..16:
        s = s + HEX_DIGITS.get(bit_and(shift_right_unsigned(h, 60 - 4 * i), 15))
    return s

def short(id: String) -> String:
    return id.slice(0, 7).get()

def tree_hash(tree: Map[String, String]) -> Int:
    var text = ""
    for name in tree.keys().sorted():
        text = text + name + " " + hex16(fnv(tree.get(name).get(""))) + "\n"
    return fnv(text)

def same_tree(a: Map[String, String], b: Map[String, String]) -> Bool:
    if a.length() != b.length():
        return False

    for name in a.keys():
        if not b.contains(name) or a.get(name).get("") != b.get(name).get(""):
            return False
    return True

def is_space(c: String) -> Bool:
    return c == " " or c == "\t" or c == "\r"

def words(line: String) -> List[String]:
    var out = List[String]()
    var cur = ""

    for c in line.chars():
        if is_space(c):
            if not cur.is_empty():
                out.append(cur)
                cur = ""
        else:
            cur = cur + c

    if not cur.is_empty():
        out.append(cur)
    return out

def rest_of(line: String) -> String:
    let cs = line.chars()
    var i = 0
    while i < cs.length() and is_space(cs[i]):
        i += 1
    while i < cs.length() and not is_space(cs[i]):
        i += 1

    var s = ""
    for k in i..cs.length():
        s = s + cs[k]
    return s.trim().clone()

def rstrip(line: String) -> String:
    let cs = line.chars()
    var n = cs.length()
    while n > 0 and is_space(cs[n - 1]):
        n -= 1

    var s = ""
    for k in 0..n:
        s = s + cs[k]
    return s

def name_char(c: String, dash: Bool) -> Bool:
    if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
        return True
    if c == "." or c == "_" or c == "/":
        return True

    return dash and c == "-"

def valid_name(name: String) -> Bool:
    let cs = name.chars()
    if cs.is_empty():
        return False

    for k in 0..cs.length():
        if not name_char(cs[k], k > 0):
            return False
    return True

def is_digits(text: String) -> Bool:
    if text.is_empty():
        return False

    for c in text.chars():
        if not (c >= "0" and c <= "9"):
            return False
    return True

def is_hex_lower(text: String) -> Bool:
    if text.is_empty():
        return False

    for c in text.chars():
        if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")):
            return False
    return True

def lines_of(content: String) -> List[String]:
    var out = List[String]()
    if content.is_empty():
        return out

    let parts = content.split("\n")
    for k in 0..parts.length() - 1:
        out.append(parts[k].clone())
    return out

def join_lines(lines: List[String]) -> String:
    if lines.is_empty():
        return ""

    return lines.join("\n") + "\n"

def same_lines(a: List[String], b: List[String]) -> Bool:
    if a.length() != b.length():
        return False

    for k in 0..a.length():
        if a[k] != b[k]:
            return False
    return True

def span(lines: List[String], start: Int, stop: Int) -> List[String]:
    var out = List[String]()
    for k in start..stop:
        out.append(lines[k].clone())
    return out

def matches(a: List[String], b: List[String]) -> List[Pair]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var table = List[Int]()
    for _idx in 0..(n + 1) * w:
        table.append(0)

    for k in 0..n:
        let i = n - 1 - k

        for l in 0..m:
            let j = m - 1 - l

            if a[i] == b[j]:
                table[i * w + j] = 1 + table[(i + 1) * w + j + 1]
            else:
                table[i * w + j] = table[(i + 1) * w + j].max(table[i * w + j + 1])

    var pairs = List[Pair]()
    var i = 0
    var j = 0

    while i < n and j < m:
        if a[i] == b[j]:
            pairs.append(Pair(a: i, b: j))
            i += 1
            j += 1
        elif table[(i + 1) * w + j] >= table[i * w + j + 1]:
            i += 1
        else:
            j += 1

    return pairs

def diff_lines(a: List[String], b: List[String]) -> List[String]:
    var out = List[String]()
    var ai = 0
    var bi = 0

    for p in matches(a, b):
        while ai < p.a:
            out.append("- " + a[ai])
            ai += 1

        while bi < p.b:
            out.append("+ " + b[bi])
            bi += 1

        out.append("  " + a[p.a])
        ai = p.a + 1
        bi = p.b + 1

    while ai < a.length():
        out.append("- " + a[ai])
        ai += 1

    while bi < b.length():
        out.append("+ " + b[bi])
        bi += 1

    return out

def merge_text(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) -> Merged:
    var ours_of = List[Int]()
    var theirs_of = List[Int]()

    for _idx in 0..base.length():
        ours_of.append(-1)
        theirs_of.append(-1)

    for p in matches(base, ours):
        ours_of[p.a] = p.b
    for p in matches(base, theirs):
        theirs_of[p.a] = p.b

    var anchors = List[Anchor]()
    for k in 0..base.length():
        if ours_of[k] >= 0 and theirs_of[k] >= 0:
            anchors.append(Anchor(b: k, o: ours_of[k], t: theirs_of[k]))
    anchors.append(Anchor(b: base.length(), o: ours.length(), t: theirs.length()))

    var out = List[String]()
    var clean = True
    var pb = -1
    var po = -1
    var pt = -1

    for k in 0..anchors.length():
        let an = anchors[k]
        let cb = span(base, pb + 1, an.b)
        let co = span(ours, po + 1, an.o)
        let ct = span(theirs, pt + 1, an.t)
        var piece = List[String]()

        if same_lines(co, cb):
            piece = ct
        elif same_lines(ct, cb) or same_lines(co, ct):
            piece = co
        else:
            clean = False
            piece.append("<<<<<<< HEAD")
            for line in co:
                piece.append(line)
            piece.append("=======")
            for line in ct:
                piece.append(line)
            piece.append(">>>>>>> " + branch)

        for line in piece:
            out.append(line)
        if k < anchors.length() - 1:
            out.append(base[an.b].clone())
        pb = an.b
        po = an.o
        pt = an.t

    return Merged(lines: out, clean: clean)

def tree_names(a: Map[String, String], b: Map[String, String]) -> Set[String]:
    var names = Set[String]()
    for n in a.keys():
        names.add(n)
    for n in b.keys():
        names.add(n)
    return names

def new_repo(input: List[String]) -> Repo:
    var branches = Map[String, String]()
    branches["main"] = ""
    return Repo(
        input: input, pos: 0, out: List[String](), commits: Map[String, Commit](),
        branches: branches, tags: Map[String, String](), work: Map[String, String](),
        index: Map[String, String](), conflicts: Set[String](), head_branch: "main",
        detached: False, detached_at: "", merging: False, merge_other: "",
        merge_name: "", next_number: 1
    )

impl Repo:
    var def emit(line: String) -> Unit:
        self.out.append(line)

    var def fail(message: String) -> Unit:
        self.out.append("error: " + message)

    var def section(title: String, items: List[String]) -> Unit:
        if items.is_empty():
            return

        self.out.append(title)
        for item in items:
            self.out.append("  " + item)

    def head_id() -> String:
        if self.detached:
            return self.detached_at.clone()

        return self.branches.get(self.head_branch).get("")

    def label() -> String:
        if self.detached:
            return "detached"

        return self.head_branch.clone()

    def tree_at(id: String) -> Map[String, String]:
        if let c = self.commits.get(id):
            return c.tree.clone()

        return Map[String, String]()

    def parents_of(id: String) -> List[String]:
        if let c = self.commits.get(id):
            return c.parents.clone()

        return List[String]()

    def message_of(id: String) -> String:
        if let c = self.commits.get(id):
            return c.message.clone()

        return ""

    def number_of(id: String) -> Int:
        if let c = self.commits.get(id):
            return c.number

        return 0

    def ancestors(id: String) -> Set[String]:
        var seen = Set[String]()
        if id.is_empty():
            return seen

        var todo = List[String]()
        todo.append(id)

        var k = 0

        while k < todo.length():
            let c = todo[k].clone()
            k += 1

            if not seen.contains(c):
                seen.add(c.clone())
                for p in self.parents_of(c):
                    todo.append(p)

        return seen

    def merge_base(cur: String, other: String) -> String:
        let mine = self.ancestors(cur)
        let theirs = self.ancestors(other)
        var best = ""
        var best_number = -1

        for id in mine.values():
            if theirs.contains(id):
                let n = self.number_of(id)

                if n > best_number:
                    best_number = n
                    best = id

        return best

    def resolve_name(name: String, spec: String) -> Found:
        if name == "HEAD":
            let h = self.head_id()
            if not h.is_empty():
                return Found(id: h, error: "")

        if let b = self.branches.get(name):
            if not b.is_empty():
                return Found(id: b.clone(), error: "")
        if let t = self.tags.get(name):
            return Found(id: t.clone(), error: "")

        if name.length() >= 4 and is_hex_lower(name):
            var found = ""
            var count = 0

            for id in self.commits.keys():
                if id.starts_with(name):
                    found = id
                    count += 1

            if count == 1:
                return Found(id: found, error: "")
            if count > 1:
                return Found(id: "", error: "ambiguous revision '" + spec + "'")

        return Found(id: "", error: "unknown revision '" + spec + "'")

    def resolve(spec: String) -> Found:
        let parts = spec.split("~")
        if parts.length() > 2:
            return Found(id: "", error: "unknown revision '" + spec + "'")

        let found = self.resolve_name(parts[0], spec)
        if parts.length() == 1 or not found.error.is_empty():
            return found

        let text = parts[1]
        let steps = text.parse_int().get(-1)
        if not is_digits(text) or steps < 0:
            return Found(id: "", error: "unknown revision '" + spec + "'")

        var id = found.id.clone()
        var k = 0

        while k < steps:
            let ps = self.parents_of(id)
            if ps.is_empty():
                return Found(id: "", error: "unknown revision '" + spec + "'")

            id = ps[0].clone()
            k += 1

        return Found(id: id, error: "")

    var def make_commit(
        tree: Map[String, String],
        parents: List[String],
        message: String
    ) -> String:
        var text = "tree " + hex16(tree_hash(tree)) + "\n"
        for p in parents:
            text = text + "parent " + p + "\n"
        text = text + "\n" + message + "\n"

        let id = hex16(fnv(text))

        if not self.commits.contains(id):
            self.commits[id.clone()] = Commit(
                id: id.clone(), tree: tree.clone(), parents: parents.clone(),
                message: message.clone(), number: self.next_number
            )
            self.next_number += 1

        return id

    var def move_head(id: String) -> Unit:
        if self.detached:
            self.detached_at = id
        else:
            self.branches[self.head_branch.clone()] = id.clone()

    var def drop_work(names: List[String]) -> Unit:
        for n in names:
            if self.work.contains(n):
                self.work.remove(n)

    var def load_tree(target: Map[String, String]) -> Unit:
        self.drop_work(self.index.keys())
        for n in target.keys():
            self.work[n.clone()] = target.get(n.clone()).get("")
        self.index = target.clone()

    def is_dirty() -> Bool:
        if not same_tree(self.index, self.tree_at(self.head_id())):
            return True

        for n in self.index.keys():
            if not self.work.contains(n):
                return True
            if self.work.get(n).get("") != self.index.get(n).get(""):
                return True

        return False

    def untracked_in(target: Map[String, String]) -> String:
        for n in target.keys().sorted():
            if not self.index.contains(n) and self.work.contains(n):
                return n
        return ""

    var def can_switch(target: Map[String, String]) -> Bool:
        if self.is_dirty():
            self.fail("local changes would be overwritten")
            return False

        let clash = self.untracked_in(target)

        if not clash.is_empty():
            self.fail("untracked file would be overwritten: " + clash)
            return False

        return True

    var def hard_reset(target: String) -> Unit:
        self.drop_work(self.index.keys())
        self.drop_work(self.tree_at(self.head_id()).keys())

        let tree = self.tree_at(target)
        for n in tree.keys():
            self.work[n.clone()] = tree.get(n.clone()).get("")
        self.index = tree.clone()
        self.move_head(target)
        self.merging = False
        self.conflicts = Set[String]()

    var def read_block() -> String:
        var body = ""

        while self.pos < self.input.length() and self.input[self.pos] != ".":
            body = body + self.input[self.pos] + "\n"
            self.pos += 1

        if self.pos < self.input.length():
            self.pos += 1
        return body

    var def run() -> Unit:
        while self.pos < self.input.length():
            let raw = self.input[self.pos].clone()
            self.pos += 1

            let toks = words(raw)

            if not toks.is_empty() and not toks[0].starts_with("#"):
                self.emit("> " + rstrip(raw))
                self.dispatch(toks, raw)

    var def dispatch(toks: List[String], raw: String) -> Unit:
        let cmd = toks[0].clone()
        var args = List[String]()
        for k in 1..toks.length():
            args.append(toks[k].clone())

        if cmd == "write" or cmd == "append":
            self.cmd_write(cmd, args)
        elif cmd == "rm":
            self.cmd_rm(args)
        elif cmd == "mv":
            self.cmd_mv(args)
        elif cmd == "cat":
            self.cmd_cat(args)
        elif cmd == "ls":
            self.cmd_ls()
        elif cmd == "add":
            self.cmd_add(args)
        elif cmd == "status":
            self.cmd_status()
        elif cmd == "commit":
            self.cmd_commit(rest_of(raw))
        elif cmd == "log":
            self.cmd_log(args)
        elif cmd == "diff":
            self.cmd_diff(args)
        elif cmd == "branch":
            self.cmd_branch(args)
        elif cmd == "tag":
            self.cmd_tag(args)
        elif cmd == "show":
            self.cmd_show(args)
        elif cmd == "checkout":
            self.cmd_checkout(args)
        elif cmd == "merge":
            self.cmd_merge(args)
        elif cmd == "reset":
            self.cmd_reset(args)
        else:
            self.fail("unknown command '" + cmd + "'")

    var def cmd_write(cmd: String, args: List[String]) -> Unit:
        if args.length() != 1:
            self.fail("usage: " + cmd + " FILE")
            return

        let body = self.read_block()
        let name = args[0].clone()

        if cmd == "write":
            self.work[name] = body
        else:
            self.work[name.clone()] = self.work.get(name.clone()).get("") + body

    var def cmd_rm(args: List[String]) -> Unit:
        if args.is_empty():
            self.fail("usage: rm FILE...")
            return

        for n in args:
            if not self.work.contains(n):
                self.fail("no such file: " + n)
                return

            self.work.remove(n)

    var def cmd_mv(args: List[String]) -> Unit:
        if args.length() != 2:
            self.fail("usage: mv OLD NEW")
            return

        let old = args[0].clone()
        let new = args[1].clone()

        if not self.work.contains(old):
            self.fail("no such file: " + old)
            return

        let content = self.work.get(old).get("")
        self.work.remove(old)
        self.work[new] = content

    var def cmd_cat(args: List[String]) -> Unit:
        if args.length() != 1:
            self.fail("usage: cat FILE")
            return

        if not self.work.contains(args[0]):
            self.fail("no such file: " + args[0])
            return

        for line in lines_of(self.work.get(args[0]).get("")):
            self.emit(line)

    var def cmd_ls() -> Unit:
        if self.work.is_empty():
            self.emit("(empty)")
            return

        for n in self.work.keys().sorted():
            self.emit(n)

    var def cmd_add(args: List[String]) -> Unit:
        if args.is_empty():
            self.fail("usage: add PATH...")
            return

        for p in args:
            if p == ".":
                for n in self.work.keys():
                    self.index[n.clone()] = self.work.get(n.clone()).get("")
                    self.conflicts.remove(n.clone())

                for n in self.index.keys():
                    if not self.work.contains(n):
                        self.index.remove(n.clone())
                        self.conflicts.remove(n.clone())
            elif self.work.contains(p):
                self.index[p.clone()] = self.work.get(p.clone()).get("")
                self.conflicts.remove(p.clone())
            elif self.index.contains(p):
                self.index.remove(p.clone())
                self.conflicts.remove(p.clone())
            elif self.conflicts.contains(p):
                self.conflicts.remove(p.clone())
            else:
                self.fail("pathspec '" + p + "' did not match any files")
                return

    var def cmd_commit(message: String) -> Unit:
        if message.is_empty():
            self.fail("empty commit message")
            return

        if not self.conflicts.is_empty():
            self.fail(
                "unresolved conflicts: " + self.conflicts.values().sorted().join(
                    " "
                )
            )
            return

        let head = self.head_id()
        var parents = List[String]()
        if not head.is_empty():
            parents.append(head.clone())

        if self.merging:
            parents.append(self.merge_other.clone())
        elif same_tree(self.index, self.tree_at(head)):
            self.fail("nothing to commit")
            return

        let id = self.make_commit(self.index.clone(), parents, message.clone())
        self.move_head(id.clone())
        if self.merging:
            self.merging = False

        let root = " (root-commit)" if head.is_empty() else ""

        self.emit("[" + self.label() + root + " " + short(id) + "] " + message)

    var def cmd_status() -> Unit:
        if self.detached:
            self.emit("HEAD detached at " + short(self.detached_at))
        else:
            self.emit("On branch " + self.head_branch)

        if self.merging:
            self.emit("merging: " + self.merge_name)

        let head_tree = self.tree_at(self.head_id())
        var staged = List[String]()

        for n in tree_names(head_tree, self.index).values().sorted():
            if not self.conflicts.contains(n):
                let in_head = head_tree.contains(n)
                let in_index = self.index.contains(n)

                if in_index and not in_head:
                    staged.append("new file: " + n)
                elif in_head and not in_index:
                    staged.append("deleted: " + n)
                elif head_tree.get(n).get("") != self.index.get(n).get(""):
                    staged.append("modified: " + n)

        var unstaged = List[String]()

        for n in self.index.keys().sorted():
            if not self.conflicts.contains(n):
                if not self.work.contains(n):
                    unstaged.append("deleted: " + n)
                elif self.work.get(n).get("") != self.index.get(n).get(""):
                    unstaged.append("modified: " + n)

        var unmerged = List[String]()
        for n in self.conflicts.values().sorted():
            unmerged.append("unmerged: " + n)

        var untracked = List[String]()
        for n in self.work.keys().sorted():
            if not self.index.contains(n) and not self.conflicts.contains(n):
                untracked.append(n)

        if (
            staged.is_empty()
            and unstaged.is_empty()
            and unmerged.is_empty()
            and untracked.is_empty()
        ):
            self.emit("nothing to commit, working tree clean")
            return

        self.section("staged:", staged)
        self.section("unstaged:", unstaged)
        self.section("conflicts:", unmerged)
        self.section("untracked:", untracked)

    var def cmd_log(args: List[String]) -> Unit:
        var limit = NO_LIMIT

        if args.length() == 2 and args[0] == "-n" and is_digits(args[1]):
            limit = args[1].parse_int().get(NO_LIMIT)
        elif args.length() != 0:
            self.fail("usage: log [-n N]")
            return

        let head = self.head_id()

        if head.is_empty():
            self.fail("no commits yet")
            return

        var nums = List[Int]()
        var by_num = Map[Int, String]()

        for id in self.ancestors(head).values():
            let n = self.number_of(id)
            nums.append(n)
            by_num[n] = id

        nums.sort()

        var shown = 0
        var k = nums.length() - 1

        while k >= 0 and shown < limit:
            let id = by_num.get(nums[k]).get("")
            let parents = self.parents_of(id)
            var line = short(id) + " " + self.message_of(id)
            if parents.length() == 2:
                line = (
                    line
                    + " (merge "
                    + short(parents[0])
                    + " "
                    + short(parents[1])
                    + ")"
                )
            self.emit(line)
            shown += 1
            k -= 1

    var def cmd_diff(args: List[String]) -> Unit:
        if args.length() > 2:
            self.fail("usage: diff [REF [REF]]")
            return

        var left = self.index.clone()
        var right = self.work.clone()

        if args.length() >= 1:
            let f = self.resolve(args[0])

            if not f.error.is_empty():
                self.fail(f.error)
                return

            left = self.tree_at(f.id)

        if args.length() == 2:
            let g = self.resolve(args[1])

            if not g.error.is_empty():
                self.fail(g.error)
                return

            right = self.tree_at(g.id)

        var changed = False

        for n in tree_names(left, right).values().sorted():
            let in_left = left.contains(n)
            let in_right = right.contains(n)
            let cl = left.get(n).get("")
            let cr = right.get(n).get("")

            if in_left != in_right or cl != cr:
                changed = True
                self.emit("diff " + n)

                if not in_left:
                    self.emit("new file")
                elif not in_right:
                    self.emit("deleted file")

                for line in diff_lines(lines_of(cl), lines_of(cr)):
                    self.emit(line)

        if not changed:
            self.emit("(no differences)")

    var def cmd_branch(args: List[String]) -> Unit:
        if args.is_empty():
            if self.detached:
                self.emit("* (HEAD detached at " + short(self.detached_at) + ")")

            for n in self.branches.keys().sorted():
                if not self.detached and n == self.head_branch:
                    self.emit("* " + n)
                else:
                    self.emit("  " + n)
        elif args.length() == 1:
            let name = args[0].clone()

            if not valid_name(name):
                self.fail("invalid branch name '" + name + "'")
                return

            if self.branches.contains(name):
                self.fail("branch '" + name + "' already exists")
                return

            let head = self.head_id()

            if head.is_empty():
                self.fail("no commits yet")
                return

            self.branches[name] = head
        elif args.length() == 2 and args[0] == "-d":
            let name = args[1].clone()

            if not self.branches.contains(name):
                self.fail("branch '" + name + "' not found")
                return

            if not self.detached and self.head_branch == name:
                self.fail("cannot delete the current branch '" + name + "'")
                return

            let target = self.branches.get(name).get("")

            if target.is_empty() or not self.ancestors(self.head_id()).contains(target):
                self.fail("branch '" + name + "' is not fully merged")
                return

            self.branches.remove(name.clone())
            self.emit("Deleted branch " + name + " (was " + short(target) + ").")
        else:
            self.fail("usage: branch [NAME | -d NAME]")

    var def cmd_tag(args: List[String]) -> Unit:
        if args.is_empty():
            for n in self.tags.keys().sorted():
                self.emit(n)
            return

        if args.length() > 2:
            self.fail("usage: tag [NAME [REF]]")
            return

        let name = args[0].clone()

        if not valid_name(name):
            self.fail("invalid tag name '" + name + "'")
            return

        if self.tags.contains(name):
            self.fail("tag '" + name + "' already exists")
            return

        let target_ref = args[1].clone() if args.length() == 2 else "HEAD"

        if target_ref == "HEAD" and self.head_id().is_empty():
            self.fail("no commits yet")
            return

        let f = self.resolve(target_ref)

        if not f.error.is_empty():
            self.fail(f.error)
            return

        self.tags[name.clone()] = f.id.clone()

    var def cmd_show(args: List[String]) -> Unit:
        if args.length() != 1:
            self.fail("usage: show REF")
            return

        let f = self.resolve(args[0])

        if not f.error.is_empty():
            self.fail(f.error)
            return

        let tree = self.tree_at(f.id)
        self.emit("commit " + f.id)
        self.emit("tree " + hex16(tree_hash(tree)))
        for p in self.parents_of(f.id):
            self.emit("parent " + p)
        self.emit("message: " + self.message_of(f.id))
        self.emit("files:")
        for n in tree.keys().sorted():
            self.emit("  " + n + " " + short(hex16(fnv(tree.get(n).get("")))))

    var def checkout_new(name: String) -> Unit:
        if not valid_name(name):
            self.fail("invalid branch name '" + name + "'")
            return

        if self.branches.contains(name):
            self.fail("branch '" + name + "' already exists")
            return

        let head = self.head_id()

        if head.is_empty():
            self.fail("no commits yet")
            return

        let tree = self.tree_at(head)
        if not self.can_switch(tree):
            return

        self.branches[name.clone()] = head.clone()
        self.load_tree(tree)
        self.head_branch = name.clone()
        self.detached = False
        self.emit("Switched to a new branch '" + name + "'")

    var def checkout_target(target: String) -> Unit:
        if self.merging:
            self.fail("merge in progress")
            return

        if self.branches.contains(target):
            if not self.detached and self.head_branch == target:
                self.emit("Already on '" + target + "'")
                return

            let tree = self.tree_at(self.branches.get(target).get(""))
            if not self.can_switch(tree):
                return

            self.load_tree(tree)
            self.head_branch = target.clone()
            self.detached = False
            self.emit("Switched to branch '" + target + "'")
            return

        let f = self.resolve(target)

        if not f.error.is_empty():
            self.fail(f.error)
            return

        let tree = self.tree_at(f.id)
        if not self.can_switch(tree):
            return

        self.load_tree(tree)
        self.detached = True
        self.detached_at = f.id.clone()
        self.emit("HEAD is now at " + short(f.id) + " " + self.message_of(f.id))

    var def cmd_checkout(args: List[String]) -> Unit:
        if args.length() == 2 and args[0] == "-b":
            self.checkout_new(args[1].clone())
        elif args.length() == 1:
            self.checkout_target(args[0].clone())
        else:
            self.fail("usage: checkout REF | checkout -b NAME")

    var def cmd_merge(args: List[String]) -> Unit:
        if args.length() == 1 and args[0] == "--abort":
            if not self.merging:
                self.fail("no merge in progress")
                return

            self.hard_reset(self.head_id())
            self.emit("Merge aborted.")
            return

        if args.length() != 1:
            self.fail("usage: merge BRANCH")
            return

        let name = args[0].clone()

        if self.merging:
            self.fail("merge in progress")
            return

        let cur = self.head_id()

        if cur.is_empty():
            self.fail("no commits yet")
            return

        let other = self.branches.get(name).get("")

        if other.is_empty():
            self.fail("unknown branch '" + name + "'")
            return

        if self.is_dirty():
            self.fail("local changes would be overwritten")
            return

        if self.ancestors(cur.clone()).contains(other.clone()):
            self.emit("Already up to date.")
            return

        if self.ancestors(other.clone()).contains(cur.clone()):
            let tree = self.tree_at(other)
            if not self.can_switch(tree):
                return

            self.load_tree(tree)
            self.move_head(other)
            self.emit("Fast-forward")
            return

        let base = self.tree_at(self.merge_base(cur.clone(), other.clone()))
        let ours = self.tree_at(cur)
        let theirs = self.tree_at(other)
        var result = Map[String, String]()
        var overrides = Map[String, String]()
        var conflicted = List[String]()
        var kinds = List[String]()
        var every = tree_names(base, ours)
        for n in theirs.keys():
            every.add(n)

        for n in every.values().sorted():
            let in_b = base.contains(n)
            let in_o = ours.contains(n)
            let in_t = theirs.contains(n)
            let b = base.get(n).get("")
            let o = ours.get(n).get("")
            let t = theirs.get(n).get("")

            if in_o == in_t and o == t:
                if in_o:
                    result[n.clone()] = o.clone()
            elif in_o == in_b and o == b:
                if in_t:
                    result[n.clone()] = t.clone()
            elif in_t == in_b and t == b:
                if in_o:
                    result[n.clone()] = o.clone()
            elif in_o != in_t:
                conflicted.append(n.clone())
                kinds.append("modify/delete")

                if in_o:
                    result[n.clone()] = o.clone()
                    overrides[n.clone()] = o.clone()
                else:
                    overrides[n.clone()] = t.clone()
            else:
                let merged = merge_text(lines_of(b), lines_of(o), lines_of(t), name)
                let text = join_lines(merged.lines)

                if merged.clean:
                    result[n.clone()] = text.clone()
                else:
                    result[n.clone()] = o.clone()
                    overrides[n.clone()] = text.clone()
                    conflicted.append(n.clone())
                    kinds.append("content" if in_b else "add/add")

        let touched = tree_names(result, overrides)

        for n in touched.values().sorted():
            if not self.index.contains(n) and self.work.contains(n):
                self.fail("untracked file would be overwritten: " + n)
                return

        for n in self.index.keys():
            if not result.contains(n) and self.work.contains(n):
                self.work.remove(n)
        for n in result.keys():
            self.work[n.clone()] = result.get(n.clone()).get("")
        for n in overrides.keys():
            self.work[n.clone()] = overrides.get(n.clone()).get("")
        self.index = result.clone()
        self.conflicts = Set[String]()
        for n in conflicted:
            self.conflicts.add(n.clone())

        if not conflicted.is_empty():
            self.merging = True
            self.merge_other = other.clone()
            self.merge_name = name.clone()

            for k in 0..conflicted.length():
                if kinds[k] == "modify/delete":
                    self.emit("CONFLICT (modify/delete): " + conflicted[k])
                else:
                    self.emit(
                        "CONFLICT (" + kinds[
                            k
                        ] + "): Merge conflict in " + conflicted[k]
                    )

            self.emit(
                "Automatic merge failed; fix conflicts and then commit the result."
            )
            return

        var parents = List[String]()
        parents.append(cur)
        parents.append(other)

        let id = self.make_commit(
            self.index.clone(), parents, "Merge branch '" + name + "'"
        )
        self.move_head(id.clone())
        self.emit("Merge made by the 'three-way' strategy.")
        self.emit(
            "[" + self.label() + " " + short(
                id
            ) + "] Merge branch '" + name + "'"
        )

    var def cmd_reset(args: List[String]) -> Unit:
        if args.is_empty() or args.length() > 2 or args[0] != "--hard":
            self.fail("usage: reset --hard [REF]")
            return

        var target = self.head_id()

        if args.length() == 2:
            let f = self.resolve(args[1])

            if not f.error.is_empty():
                self.fail(f.error)
                return

            target = f.id.clone()

        if target.is_empty():
            self.fail("no commits yet")
            return

        self.hard_reset(target.clone())
        self.emit("HEAD is now at " + short(target) + " " + self.message_of(target))

export def main() -> Int:
    var repo = new_repo(read_lines(stdin()).get())
    repo.run()
    if not repo.out.is_empty():
        stdout().write(join_lines(repo.out)).get()
    return 0
