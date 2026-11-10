import (
    stdin from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
    wrapping_multiply, bit_xor, bit_and, shift_right_unsigned from "@std/math/math.ms",
)

let FNV_OFFSET = -3750763034362895579
let FNV_PRIME = 1099511628211
let HEX = "0123456789abcdef"
let DIGITS = "0123456789"
let NAME_FIRST = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/"
let NAME_REST = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-"

type Resolved:
    id: String
    error: String

type Merged:
    text: String
    clean: Bool

type Repo:
    work: Map[String, String]
    index: Map[String, String]
    commit_tree: Map[String, Map[String, String]]
    commit_parents: Map[String, List[String]]
    commit_msg: Map[String, String]
    commit_num: Map[String, Int]
    branches: Map[String, String]
    tags: Map[String, String]
    attached: Bool
    head_name: String
    merging: Bool
    merge_other: String
    merge_branch: String
    conflicts: Set[String]
    created: Int

// ---------- hashing and text helpers ----------

fn fnv(s: String) Int:
    var h = FNV_OFFSET
    let bs = s.as_bytes()

    for i in 0..bs.length():
        h = bit_xor(h, bs.get(i).to_int())
        h = wrapping_multiply(h, FNV_PRIME)

    return h

fn hex16(h: Int) String:
    var out = ""
    var k = 60

    while k >= 0:
        out = out + HEX.get(bit_and(shift_right_unsigned(h, k), 15))
        k -= 4

    return out

fn short(id: String) String:
    return id.slice(0, 7).get()

fn all_digits(s: String) Bool:
    if s.is_empty():
        return false

    for k in 0..s.length():
        if not DIGITS.contains(s.get(k)):
            return false
    return true

fn is_hex_prefix(s: String) Bool:
    if s.length() < 4:
        return false

    for k in 0..s.length():
        if not HEX.contains(s.get(k)):
            return false
    return true

fn valid_name(s: String) Bool:
    if s.is_empty():
        return false
    if not NAME_FIRST.contains(s.get(0)):
        return false

    for k in 1..s.length():
        if not NAME_REST.contains(s.get(k)):
            return false
    return true

fn words(line: String) List[String]:
    var out = List[String]()
    for w in line.split("\t").join(" ").split(" "):
        if w != "":
            out.append(w)
    return out

fn tail(xs: List[String]) List[String]:
    var out = List[String]()
    for k in 1..xs.length():
        out.append(xs[k].clone())
    return out

fn split_lines(content: String) List[String]:
    if content == "":
        return List[String]()

    var parts = content.split("\n")
    let _last = parts.pop()
    return parts

fn join_lines(lines: List[String]) String:
    var s = ""
    for l in lines:
        s = s + l + "\n"
    return s

fn sub(xs: List[String], from: Int, to: Int) List[String]:
    var out = List[String]()
    var k = from

    while k < to:
        out.append(xs[k].clone())
        k += 1

    return out

fn append_all(var out: List[String], xs: List[String]) Unit:
    for x in xs:
        out.append(x.clone())

fn list_eq(a: List[String], b: List[String]) Bool:
    if a.length() != b.length():
        return false

    for k in 0..a.length():
        if a[k] != b[k]:
            return false
    return true

// ---------- trees ----------

// Whether `key` has the same presence and content in both maps.
fn entry_eq(a: Map[String, String], b: Map[String, String], key: String) Bool:
    if let av = a.get(key):
        if let bv = b.get(key):
            return av == bv

        return false

    return not b.contains(key)

fn same_tree(a: Map[String, String], b: Map[String, String]) Bool:
    if a.length() != b.length():
        return false

    for k in a.keys():
        if not entry_eq(a, b, k):
            return false
    return true

fn sorted_union(
    a: Map[String, String],
    b: Map[String, String],
    c: Map[String, String]
) List[String]:
    var s = Set[String]()
    for k in a.keys():
        s.add(k)
    for k in b.keys():
        s.add(k)
    for k in c.keys():
        s.add(k)
    return s.values().sorted()

fn tree_text(tree: Map[String, String]) String:
    var text = ""
    for name in tree.keys().sorted():
        if let c = tree.get(name):
            text = text + name + " " + hex16(fnv(c)) + "\n"
    return text

fn tree_hash(tree: Map[String, String]) String:
    return hex16(fnv(tree_text(tree)))

// ---------- repository access ----------

fn new_repo() Repo:
    var r = Repo(
        work: Map[String, String](), index: Map[String, String](),
        commit_tree: Map[String, Map[String, String]](),
        commit_parents: Map[String, List[String]](), commit_msg: Map[String, String](),
        commit_num: Map[String, Int](), branches: Map[String, String](),
        tags: Map[String, String](), attached: true, head_name: "main", merging: false,
        merge_other: "", merge_branch: "", conflicts: Set[String](), created: 0
    )
    r.branches.add("main", "")
    return r

fn head_commit(r: Repo) String:
    if r.attached:
        return r.branches.get_or(r.head_name.clone(), "")

    return r.head_name.clone()

fn head_label(r: Repo) String:
    if r.attached:
        return r.head_name.clone()

    return "detached".to_string()

fn move_head(var r: Repo, id: String) Unit:
    if r.attached:
        r.branches.add(r.head_name.clone(), id)
    else:
        r.head_name = id.clone()

fn parents_of(r: Repo, c: String) List[String]:
    if let ps = r.commit_parents.get(c):
        return ps.clone()

    return List[String]()

fn tree_of(r: Repo, id: String) Map[String, String]:
    if id == "":
        return Map[String, String]()
    if let t = r.commit_tree.get(id):
        return t.clone()

    return Map[String, String]()

fn msg_of(r: Repo, id: String) String:
    return r.commit_msg.get_or(id, "")

fn num_of(r: Repo, id: String) Int:
    return r.commit_num.get_or(id, 0)

fn ancestors(r: Repo, start: String) Set[String]:
    var seen = Set[String]()
    if start == "":
        return seen

    var stack = [start]

    while not stack.is_empty():
        let c = stack.pop().get()

        if not seen.contains(c):
            seen.add(c.clone())
            for p in parents_of(r, c):
                stack.append(p.clone())

    return seen

fn merge_base(r: Repo, a: String, b: String) String:
    let anc_a = ancestors(r, a)
    let anc_b = ancestors(r, b)
    var best = ""
    var best_num = -1

    for c in anc_a.values():
        if anc_b.contains(c):
            let n = num_of(r, c)

            if n > best_num:
                best = c
                best_num = n

    return best

fn store_commit(
    var r: Repo, tree: Map[String, String], parents: List[String], msg: String
) String:
    var text = "tree " + tree_hash(tree) + "\n"
    for p in parents:
        text = text + "parent " + p + "\n"
    text = text + "\n" + msg + "\n"

    let id = hex16(fnv(text))

    if not r.commit_num.contains(id):
        r.created += 1
        r.commit_num.add(id.clone(), r.created)
        r.commit_tree.add(id.clone(), tree.clone())
        r.commit_parents.add(id.clone(), parents.clone())
        r.commit_msg.add(id.clone(), msg)

    return id

fn resolve(r: Repo, spec: String) Resolved:
    let parts = spec.split("~")
    var base = spec.clone()
    var steps = 0

    if parts.length() == 2:
        base = parts[0].clone()

        let s = parts[1].clone()
        if not all_digits(s):
            return Resolved(id: "", error: "unknown revision '" + spec + "'")

        if let v = s.parse_int():
            steps = v
        else:
            return Resolved(id: "", error: "unknown revision '" + spec + "'")
    else if parts.length() > 2:
        return Resolved(id: "", error: "unknown revision '" + spec + "'")

    var id = ""

    if base == "HEAD":
        id = head_commit(r)
    else if r.branches.get_or(base, "") != "":
        id = r.branches.get_or(base, "")
    else if r.tags.contains(base):
        id = r.tags.get_or(base, "")
    else if is_hex_prefix(base):
        var count = 0
        var found = ""

        for k in r.commit_num.keys():
            if k.starts_with(base):
                count += 1
                found = k

        if count > 1:
            return Resolved(id: "", error: "ambiguous revision '" + spec + "'")

        id = found

    if id == "":
        return Resolved(id: "", error: "unknown revision '" + spec + "'")

    var k = 0

    while k < steps:
        let ps = parents_of(r, id)
        if ps.is_empty():
            return Resolved(id: "", error: "unknown revision '" + spec + "'")

        id = ps[0].clone()
        k += 1

    return Resolved(id: id, error: "")

// ---------- line diff and three-way merge ----------

// For each line of a, the index of its matching line in b, or -1.
fn match_map(a: List[String], b: List[String]) List[Int]:
    let n = a.length()
    let m = b.length()
    let w = m + 1
    var tbl = List[Int]()
    for k in 0..(n + 1) * w:
        tbl.append(0)

    var i = n - 1

    while i >= 0:
        var j = m - 1

        while j >= 0:
            if a[i] == b[j]:
                tbl[i * w + j] = 1 + tbl[(i + 1) * w + j + 1]
            else if tbl[(i + 1) * w + j] >= tbl[i * w + j + 1]:
                tbl[i * w + j] = tbl[(i + 1) * w + j]
            else:
                tbl[i * w + j] = tbl[i * w + j + 1]

            j -= 1

        i -= 1

    var ma = List[Int]()
    for k in 0..n:
        ma.append(-1)

    var x = 0
    var y = 0

    while x < n and y < m:
        if a[x] == b[y]:
            ma[x] = y
            x += 1
            y += 1
        else if tbl[(x + 1) * w + y] >= tbl[x * w + y + 1]:
            x += 1
        else:
            y += 1

    return ma

fn line_diff(a: List[String], b: List[String]) List[String]:
    let ma = match_map(a, b)
    var out = List[String]()
    var pa = 0
    var pb = 0

    for x in 0..a.length():
        if ma[x] >= 0:
            let y = ma[x]

            while pa < x:
                out.append("- " + a[pa])
                pa += 1

            while pb < y:
                out.append("+ " + b[pb])
                pb += 1

            out.append("  " + a[x])
            pa = x + 1
            pb = y + 1

    while pa < a.length():
        out.append("- " + a[pa])
        pa += 1

    while pb < b.length():
        out.append("+ " + b[pb])
        pb += 1

    return out

// Returns true when the chunk is a conflict.
fn resolve_chunk(
    var out: List[String], bc: List[String], oc: List[String], tc: List[String],
    branch: String
) Bool:
    if list_eq(oc, bc):
        append_all(var out, tc)
        return false

    if list_eq(tc, bc):
        append_all(var out, oc)
        return false

    if list_eq(oc, tc):
        append_all(var out, oc)
        return false

    out.append("<<<<<<< HEAD")
    append_all(var out, oc)
    out.append("=======")
    append_all(var out, tc)
    out.append(">>>>>>> " + branch)
    return true

fn merge3(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Merged:
    let bo = match_map(base, ours)
    let bt = match_map(base, theirs)
    var out = List[String]()
    var clean = true
    var pb = 0
    var po = 0
    var pt = 0

    for s in 0..base.length():
        if bo[s] >= 0 and bt[s] >= 0:
            if resolve_chunk(
                var out, sub(base, pb, s), sub(ours, po, bo[s]), sub(theirs, pt, bt[s]),
                branch
            ):
                clean = false
            out.append(base[s].clone())
            pb = s + 1
            po = bo[s] + 1
            pt = bt[s] + 1

    if resolve_chunk(
        var out, sub(base, pb, base.length()), sub(ours, po, ours.length()),
        sub(theirs, pt, theirs.length()), branch
    ):
        clean = false
    return Merged(text: join_lines(out), clean: clean)

// ---------- working tree / index operations ----------

// Empty when the switch is safe; otherwise the error message.
fn dirty_check(r: Repo) String:
    if not same_tree(r.index, tree_of(r, head_commit(r))):
        return "local changes would be overwritten"

    for name in r.index.keys():
        if not entry_eq(r.work, r.index, name):
            return "local changes would be overwritten"
    return ""

fn untracked_check(r: Repo, target: Map[String, String]) String:
    for name in target.keys().sorted():
        if r.work.contains(name) and not r.index.contains(name):
            return "untracked file would be overwritten: " + name
    return ""

// Sets index and working tree to `target`, as checkout does.
fn switch_tree(var r: Repo, target: Map[String, String]) Unit:
    for name in r.index.keys():
        r.work.remove(name)
    for name in target.keys():
        r.work.add(name.clone(), target.get_or(name, "").clone())
    r.index.clear()
    for name in target.keys():
        r.index.add(name.clone(), target.get_or(name, "").clone())

// `reset --hard` to `target`.
fn reset_hard(var r: Repo, target: String) Unit:
    let target_tree = tree_of(r, target)
    let old_head = tree_of(r, head_commit(r))
    for name in r.index.keys():
        r.work.remove(name)
    for name in old_head.keys():
        r.work.remove(name)
    for name in target_tree.keys():
        r.work.add(name.clone(), target_tree.get_or(name, "").clone())
    r.index.clear()
    for name in target_tree.keys():
        r.index.add(name.clone(), target_tree.get_or(name, "").clone())
    move_head(var r, target)
    r.merging = false
    r.merge_other = ""
    r.merge_branch = ""
    r.conflicts.clear()

// ---------- commands ----------

fn cmd_write(var r: Repo, file: String, block: List[String], append: Bool) Unit:
    var content = join_lines(block)
    if append:
        if let old = r.work.get(file):
            content = old + content
    r.work.add(file, content)

fn cmd_rm(var r: Repo, files: List[String]) Unit:
    if files.is_empty():
        print("error: usage: rm FILE...")
        return

    for f in files:
        if not r.work.contains(f):
            print("error: no such file: " + f)
            return

        r.work.remove(f)

fn cmd_mv(var r: Repo, args: List[String]) Unit:
    if args.length() != 2:
        print("error: usage: mv OLD NEW")
        return

    if let content = r.work.get(args[0]):
        let saved = content.clone()
        r.work.remove(args[0].clone())
        r.work.add(args[1].clone(), saved)
    else:
        print("error: no such file: " + args[0])

fn cmd_cat(r: Repo, args: List[String]) Unit:
    if args.length() != 1:
        print("error: usage: cat FILE")
        return

    if let content = r.work.get(args[0]):
        for l in split_lines(content):
            print(l)
    else:
        print("error: no such file: " + args[0])

fn cmd_ls(r: Repo) Unit:
    let names = r.work.keys().sorted()
    if names.is_empty():
        print("(empty)")
    for n in names:
        print(n)

fn cmd_add(var r: Repo, paths: List[String]) Unit:
    if paths.is_empty():
        print("error: usage: add PATH...")
        return

    for p in paths:
        if p == ".":
            for name in r.work.keys():
                r.index.add(name.clone(), r.work.get_or(name, "").clone())
                r.conflicts.remove(name)

            for name in r.index.keys():
                if not r.work.contains(name):
                    r.index.remove(name.clone())
                    r.conflicts.remove(name)
        else if r.work.contains(p):
            r.index.add(p.clone(), r.work.get_or(p, "").clone())
            r.conflicts.remove(p)
        else if r.index.contains(p):
            r.index.remove(p.clone())
            r.conflicts.remove(p)
        else if r.conflicts.contains(p):
            r.conflicts.remove(p)
        else:
            print("error: pathspec '" + p + "' did not match any files")
            return

fn cmd_status(r: Repo) Unit:
    if r.attached:
        print("On branch " + r.head_name)
    else:
        print("HEAD detached at " + short(head_commit(r)))

    if r.merging:
        print("merging: " + r.merge_branch)

    let head = tree_of(r, head_commit(r))
    var any = false
    var staged = List[String]()

    for name in sorted_union(head, r.index, Map[String, String]()):
        if r.conflicts.contains(name):
            continue

        if r.index.contains(name) and not head.contains(name):
            staged.append("new file: " + name)
        else if head.contains(name) and not r.index.contains(name):
            staged.append("deleted: " + name)
        else if not entry_eq(head, r.index, name):
            staged.append("modified: " + name)

    var unstaged = List[String]()

    for name in r.index.keys().sorted():
        if r.conflicts.contains(name):
            continue

        if not r.work.contains(name):
            unstaged.append("deleted: " + name)
        else if not entry_eq(r.work, r.index, name):
            unstaged.append("modified: " + name)

    var conflicted = r.conflicts.values().sorted()
    var untracked = List[String]()
    for name in r.work.keys().sorted():
        if not r.index.contains(name) and not r.conflicts.contains(name):
            untracked.append(name)

    if not staged.is_empty():
        any = true
        print("staged:")
        for s in staged:
            print("  " + s)

    if not unstaged.is_empty():
        any = true
        print("unstaged:")
        for s in unstaged:
            print("  " + s)

    if not conflicted.is_empty():
        any = true
        print("conflicts:")
        for s in conflicted:
            print("  unmerged: " + s)

    if not untracked.is_empty():
        any = true
        print("untracked:")
        for s in untracked:
            print("  " + s)

    if not any:
        print("nothing to commit, working tree clean")

fn cmd_commit(var r: Repo, msg: String) Unit:
    if msg == "":
        print("error: empty commit message")
        return

    if not r.conflicts.is_empty():
        print("error: unresolved conflicts: " + r.conflicts.values().sorted().join(" "))
        return

    let hc = head_commit(r)
    var parents = List[String]()
    if hc != "":
        parents.append(hc.clone())

    if r.merging:
        parents.append(r.merge_other.clone())
    else if same_tree(r.index, tree_of(r, hc)):
        print("nothing to commit")
        return

    let id = store_commit(var r, r.index.clone(), parents.clone(), msg.clone())
    let root = parents.is_empty()
    move_head(var r, id.clone())

    let label = head_label(r)
    r.merging = false
    r.merge_other = ""
    r.merge_branch = ""
    r.conflicts.clear()

    if root:
        print("[" + label + " (root-commit) " + short(id) + "] " + msg)
    else:
        print("[" + label + " " + short(id) + "] " + msg)

fn cmd_log(r: Repo, limit: Int) Unit:
    let hc = head_commit(r)

    if hc == "":
        print("no commits yet")
        return

    var nums = List[Int]()
    var by_num = Map[Int, String]()

    for c in ancestors(r, hc).values():
        let n = num_of(r, c)
        nums.append(n)
        by_num.add(n, c)

    nums.sort()
    nums.reverse()

    var shown = 0

    for n in nums:
        if limit >= 0 and shown >= limit:
            break

        if let c = by_num.get(n):
            let ps = parents_of(r, c)
            var line = short(c) + " " + msg_of(r, c)
            if ps.length() == 2:
                line = line + " (merge " + short(ps[0]) + " " + short(ps[1]) + ")"
            print(line)
            shown += 1

fn cmd_diff(r: Repo, args: List[String]) Unit:
    if args.length() > 2:
        print("error: usage: diff [REF [REF]]")
        return

    var left = r.index.clone()
    var right = r.work.clone()

    if args.length() == 1:
        let res = resolve(r, args[0].clone())

        if res.error != "":
            print("error: " + res.error)
            return

        left = tree_of(r, res.id)
    else if args.length() == 2:
        let ra = resolve(r, args[0].clone())

        if ra.error != "":
            print("error: " + ra.error)
            return

        let rb = resolve(r, args[1].clone())

        if rb.error != "":
            print("error: " + rb.error)
            return

        left = tree_of(r, ra.id)
        right = tree_of(r, rb.id)

    var any = false

    for name in sorted_union(left, right, Map[String, String]()):
        if entry_eq(left, right, name):
            continue

        any = true
        print("diff " + name)

        if not left.contains(name):
            print("new file")
        else if not right.contains(name):
            print("deleted file")

        let a = split_lines(left.get_or(name, ""))
        let b = split_lines(right.get_or(name, ""))
        for l in line_diff(a, b):
            print(l)

    if not any:
        print("(no differences)")

fn cmd_show(r: Repo, args: List[String]) Unit:
    if args.length() != 1:
        print("error: usage: show REF")
        return

    let res = resolve(r, args[0].clone())

    if res.error != "":
        print("error: " + res.error)
        return

    let id = res.id
    let tree = tree_of(r, id)
    print("commit " + id)
    print("tree " + tree_hash(tree))
    for p in parents_of(r, id):
        print("parent " + p)
    print("message: " + msg_of(r, id))
    print("files:")
    for name in tree.keys().sorted():
        print("  " + name + " " + short(hex16(fnv(tree.get_or(name, "")))))

fn cmd_branch(var r: Repo, args: List[String]) Unit:
    if args.length() == 0:
        if not r.attached:
            print("* (HEAD detached at " + short(head_commit(r)) + ")")

        for name in r.branches.keys().sorted():
            if r.attached and name == r.head_name:
                print("* " + name)
            else:
                print("  " + name)

        return

    if args.length() == 1:
        let name = args[0]

        if not valid_name(name):
            print("error: invalid branch name '" + name + "'")
            return

        if r.branches.contains(name):
            print("error: branch '" + name + "' already exists")
            return

        let hc = head_commit(r)

        if hc == "":
            print("error: no commits yet")
            return

        r.branches.add(name.clone(), hc)
        return

    if args.length() == 2 and args[0] == "-d":
        let name = args[1]

        if not r.branches.contains(name):
            print("error: branch '" + name + "' not found")
            return

        if r.attached and r.head_name == name:
            print("error: cannot delete the current branch '" + name + "'")
            return

        let bc = r.branches.get_or(name, "")

        if bc == "" or not ancestors(r, head_commit(r)).contains(bc):
            print("error: branch '" + name + "' is not fully merged")
            return

        r.branches.remove(name.clone())
        print("Deleted branch " + name + " (was " + short(bc) + ").")
        return

    print("error: usage: branch [NAME | -d NAME]")

fn cmd_tag(var r: Repo, args: List[String]) Unit:
    if args.length() == 0:
        for name in r.tags.keys().sorted():
            print(name)
        return

    if args.length() > 2:
        print("error: usage: tag [NAME [REF]]")
        return

    let name = args[0]

    if not valid_name(name):
        print("error: invalid tag name '" + name + "'")
        return

    if r.tags.contains(name):
        print("error: tag '" + name + "' already exists")
        return

    var spec = "HEAD"
    if args.length() == 2:
        spec = args[1].clone()

    if spec == "HEAD" and head_commit(r) == "":
        print("error: no commits yet")
        return

    let res = resolve(r, spec)

    if res.error != "":
        print("error: " + res.error)
        return

    r.tags.add(name.clone(), res.id)

fn cmd_checkout(var r: Repo, args: List[String]) Unit:
    if args.length() == 2 and args[0] == "-b":
        let name = args[1]

        if not valid_name(name):
            print("error: invalid branch name '" + name + "'")
            return

        if r.branches.contains(name):
            print("error: branch '" + name + "' already exists")
            return

        let hc = head_commit(r)

        if hc == "":
            print("error: no commits yet")
            return

        let d = dirty_check(r)

        if d != "":
            print("error: " + d)
            return

        let u = untracked_check(r, tree_of(r, hc))

        if u != "":
            print("error: " + u)
            return

        r.branches.add(name.clone(), hc)
        r.attached = true
        r.head_name = name.clone()
        print("Switched to a new branch '" + name + "'")
        return

    if args.length() != 1:
        print("error: usage: checkout REF | checkout -b NAME")
        return

    if r.merging:
        print("error: merge in progress")
        return

    let target = args[0]

    if r.branches.contains(target):
        if r.attached and r.head_name == target:
            print("Already on '" + target + "'")
            return

        let bc = r.branches.get_or(target, "")
        let target_tree = tree_of(r, bc)
        let d = dirty_check(r)

        if d != "":
            print("error: " + d)
            return

        let u = untracked_check(r, target_tree)

        if u != "":
            print("error: " + u)
            return

        switch_tree(var r, target_tree)
        r.attached = true
        r.head_name = target.clone()
        print("Switched to branch '" + target + "'")
        return

    let res = resolve(r, target.clone())

    if res.error != "":
        print("error: " + res.error)
        return

    let target_tree = tree_of(r, res.id)
    let d = dirty_check(r)

    if d != "":
        print("error: " + d)
        return

    let u = untracked_check(r, target_tree)

    if u != "":
        print("error: " + u)
        return

    switch_tree(var r, target_tree)
    r.attached = false
    r.head_name = res.id.clone()
    print("HEAD is now at " + short(res.id) + " " + msg_of(r, res.id))

fn cmd_reset(var r: Repo, args: List[String]) Unit:
    if args.length() < 1 or args.length() > 2 or args[0] != "--hard":
        print("error: usage: reset --hard [REF]")
        return

    var hc = head_commit(r)

    if args.length() == 1 or args[1] == "HEAD":
        if hc == "":
            print("error: no commits yet")
            return
    else:
        let res = resolve(r, args[1].clone())

        if res.error != "":
            print("error: " + res.error)
            return

        hc = res.id.clone()

    reset_hard(var r, hc.clone())
    print("HEAD is now at " + short(hc) + " " + msg_of(r, hc))

fn cmd_merge_abort(var r: Repo) Unit:
    if not r.merging:
        print("error: no merge in progress")
        return

    reset_hard(var r, head_commit(r))
    print("Merge aborted.")

fn cmd_merge(var r: Repo, args: List[String]) Unit:
    if args.length() == 1 and args[0] == "--abort":
        cmd_merge_abort(var r)
        return

    if args.length() != 1:
        print("error: usage: merge BRANCH")
        return

    if r.merging:
        print("error: merge in progress")
        return

    let hc = head_commit(r)

    if hc == "":
        print("error: no commits yet")
        return

    let bname = args[0]

    if not r.branches.contains(bname) or r.branches.get_or(bname, "") == "":
        print("error: unknown branch '" + bname + "'")
        return

    let oc = r.branches.get_or(bname, "")
    let d = dirty_check(r)

    if d != "":
        print("error: " + d)
        return

    if oc == hc or ancestors(r, hc.clone()).contains(oc):
        print("Already up to date.")
        return

    if ancestors(r, oc.clone()).contains(hc):
        let target_tree = tree_of(r, oc)
        let u = untracked_check(r, target_tree)

        if u != "":
            print("error: " + u)
            return

        switch_tree(var r, target_tree)
        move_head(var r, oc.clone())
        print("Fast-forward")
        return

    // Three-way merge.
    let base_id = merge_base(r, hc.clone(), oc.clone())
    let base_tree = tree_of(r, base_id)
    let ours = tree_of(r, hc)
    let theirs = tree_of(r, oc)
    var result = Map[String, String]()
    var overrides = Map[String, String]()
    var kinds = Map[String, String]()
    let names = sorted_union(base_tree, ours, theirs)

    for nm in names:
        if entry_eq(ours, theirs, nm):
            if let v = ours.get(nm):
                result.add(nm.clone(), v.clone())
        else if entry_eq(ours, base_tree, nm):
            if let v = theirs.get(nm):
                result.add(nm.clone(), v.clone())
        else if entry_eq(theirs, base_tree, nm):
            if let v = ours.get(nm):
                result.add(nm.clone(), v.clone())
        else if not ours.contains(nm) or not theirs.contains(nm):
            kinds.add(nm.clone(), "modify/delete")

            if let v = ours.get(nm):
                result.add(nm.clone(), v.clone())
                overrides.add(nm.clone(), v.clone())
            else:
                overrides.add(nm.clone(), theirs.get_or(nm, "").clone())
        else:
            let bl = split_lines(base_tree.get_or(nm, ""))
            let merged = merge3(
                bl, split_lines(ours.get_or(nm, "")),
                split_lines(theirs.get_or(nm, "")), bname
            )

            if merged.clean:
                result.add(nm.clone(), merged.text.clone())
            else:
                result.add(nm.clone(), ours.get_or(nm, "").clone())
                overrides.add(nm.clone(), merged.text.clone())

                if base_tree.contains(nm):
                    kinds.add(nm.clone(), "content")
                else:
                    kinds.add(nm.clone(), "add/add")

    for nm in names:
        if (
            (result.contains(nm) or overrides.contains(nm))
            and r.work.contains(nm)
            and not r.index.contains(nm)
        ):
            print("error: untracked file would be overwritten: " + nm)
            return

    // Apply to working tree and index.
    for nm in r.index.keys():
        if not result.contains(nm):
            r.work.remove(nm)
    for nm in result.keys():
        if not overrides.contains(nm):
            r.work.add(nm.clone(), result.get_or(nm, "").clone())
    for nm in overrides.keys():
        r.work.add(nm.clone(), overrides.get_or(nm, "").clone())
    r.index.clear()
    for nm in result.keys():
        r.index.add(nm.clone(), result.get_or(nm, "").clone())

    if kinds.is_empty():
        var parents = List[String]()
        parents.append(hc.clone())
        parents.append(oc.clone())

        let msg = "Merge branch '" + bname + "'"
        let id = store_commit(var r, r.index.clone(), parents, msg.clone())
        move_head(var r, id.clone())
        print("Merge made by the 'three-way' strategy.")
        print("[" + head_label(r) + " " + short(id) + "] " + msg)
        return

    r.merging = true
    r.merge_other = oc.clone()
    r.merge_branch = bname.clone()

    for nm in kinds.keys().sorted():
        r.conflicts.add(nm.clone())

        let kind = kinds.get_or(nm, "")

        if kind == "modify/delete":
            print("CONFLICT (modify/delete): " + nm)
        else:
            print("CONFLICT (" + kind + "): Merge conflict in " + nm)

    print("Automatic merge failed; fix conflicts and then commit the result.")

// ---------- driver ----------

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get()
    var lines = text.split("\n")
    if lines.length() > 0 and text != "":
        let _last = lines.pop()

    let n = lines.length()
    var r = new_repo()
    var i = 0

    while i < n:
        let raw = lines[i].clone()
        i += 1

        let t = raw.trim()
        if t == "" or t.starts_with("#"):
            continue

        print("> " + raw.trim_end())

        let w = words(raw)
        let cmd = w[0].clone()
        let args = tail(w)

        if cmd == "write" or cmd == "append":
            if args.length() != 1:
                print("error: usage: " + cmd + " FILE")
            else:
                var block = List[String]()

                while i < n and lines[i] != ".":
                    block.append(lines[i].clone())
                    i += 1

                if i < n:
                    i += 1
                cmd_write(var r, args[0].clone(), block, cmd == "append")
        else if cmd == "rm":
            cmd_rm(var r, args)
        else if cmd == "mv":
            cmd_mv(var r, args)
        else if cmd == "cat":
            cmd_cat(r, args)
        else if cmd == "ls":
            cmd_ls(r)
        else if cmd == "add":
            cmd_add(var r, args)
        else if cmd == "status":
            cmd_status(r)
        else if cmd == "commit":
            let norm = raw.trim().split("\t").join(" ")
            var msg = ""
            if let k = norm.index_of(" "):
                msg = norm.slice_scalars(k, norm.length()).get().trim()
            cmd_commit(var r, msg)
        else if cmd == "log":
            if args.length() == 0:
                cmd_log(r, -1)
            else if args.length() == 2 and args[0] == "-n" and all_digits(args[1]):
                var limit = 1000000000
                if let v = args[1].parse_int():
                    limit = v
                cmd_log(r, limit)
            else:
                print("error: usage: log [-n N]")
        else if cmd == "diff":
            cmd_diff(r, args)
        else if cmd == "branch":
            cmd_branch(var r, args)
        else if cmd == "tag":
            cmd_tag(var r, args)
        else if cmd == "show":
            cmd_show(r, args)
        else if cmd == "checkout":
            cmd_checkout(var r, args)
        else if cmd == "reset":
            cmd_reset(var r, args)
        else if cmd == "merge":
            cmd_merge(var r, args)
        else:
            print("error: unknown command '" + cmd + "'")

    return 0
