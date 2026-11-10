import stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import wrapping_multiply, bit_xor, bit_and, shift_right from "@std/math/math.ms"

type Commit:
    tree: Map[String, String]
    parents: List[String]
    message: String
    seq: Int

type Repo:
    working: Map[String, String]
    index: Map[String, String]
    commits: Map[String, Commit]
    order: List[String]
    branches: Map[String, String]
    tags: Map[String, String]
    attached: Bool
    head_branch: String
    head_commit: String
    conflicts: Set[String]
    merging: Bool
    merge_other: String
    merge_branch: String

type Resolved:
    id: String
    err: String

type Merged:
    text: String
    clean: Bool

// ---------- output and input ----------

fn emit(s: String) Unit:
    stdout().write(s + "\n").get()

fn err_out(s: String) Unit:
    stdout().write("error: " + s + "\n").get()

fn read_input() List[String]!:
    var out = List[String]()
    for line in lines(stdin()):
        out.append(line)
    return ok(out)

// ---------- hashing ----------

fn hash_text(s: String) Int:
    var h = -3750763034362895579
    bs := s.as_bytes()

    for i in 0..bs.length():
        h = bit_xor(h, bs.get(i).to_int())
        h = wrapping_multiply(h, 1099511628211)

    return h

fn hex16(h: Int) String:
    digits := "0123456789abcdef"
    var out = ""

    for i in 0..16:
        d := bit_and(shift_right(h, (15 - i) * 4), 15)
        out += digits.slice(d, d + 1).get()

    return out

fn short(id: String) String:
    return id.slice(0, 7).get()

// ---------- content helpers ----------

// content is each line followed by "\n"
fn enc(xs: List[String]) String:
    var out = ""
    for x in xs:
        out += x + "\n"
    return out

fn dec(content: String) List[String]:
    var out = List[String]()
    if content == "":
        return out

    parts := content.split("\n")
    for k in 0..parts.length() - 1:
        out.append(parts[k].clone())
    return out

fn sub(xs: List[String], a: Int, b: Int) List[String]:
    var out = List[String]()
    if a >= b:
        return out

    for k in a..b:
        out.append(xs[k].clone())
    return out

fn max_int(a: Int, b: Int) Int:
    if a >= b:
        return a

    return b

fn is_digits(s: String) Bool:
    if s == "":
        return false

    for c in s.split(""):
        if not "0123456789".contains(c):
            return false
    return true

fn is_hex_prefix(s: String) Bool:
    if s.length() < 4:
        return false

    for c in s.split(""):
        if not "0123456789abcdef".contains(c):
            return false
    return true

fn name_ok(s: String) Bool:
    if s == "":
        return false

    first_set := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/"
    rest_set := first_set + "-"
    cs := s.split("")

    for k in 0..cs.length():
        if k == 0:
            if not first_set.contains(cs[k]):
                return false
        else:
            if not rest_set.contains(cs[k]):
                return false

    return true

fn sorted_keys(m: Map[String, String]) List[String]:
    var ks = m.keys()
    ks.sort()
    return ks

fn union_names(
    a: Map[String, String],
    b: Map[String, String],
    c: Map[String, String]
) List[String]:
    var s = Set[String]()
    for n in a.keys():
        s.add(n.clone())
    for n in b.keys():
        s.add(n.clone())
    for n in c.keys():
        s.add(n.clone())

    var out = s.values()
    out.sort()
    return out

fn maps_equal(a: Map[String, String], b: Map[String, String]) Bool:
    if a.length() != b.length():
        return false

    for k in a.keys():
        if not b.contains(k):
            return false
        if a.get(k).get("") != b.get(k).get(""):
            return false

    return true

// ---------- trees and commits ----------

fn tree_hash(tree: Map[String, String]) String:
    var text = ""
    for n in sorted_keys(tree):
        text += n + " " + hex16(hash_text(tree.get(n).get(""))) + "\n"
    return hex16(hash_text(text))

fn commit_id(tree: Map[String, String], parents: List[String], message: String) String:
    var text = "tree " + tree_hash(tree) + "\n"
    for p in parents:
        text += "parent " + p + "\n"
    text += "\n" + message + "\n"
    return hex16(hash_text(text))

fn make_commit(
    var r: Repo, tree: Map[String, String], parents: List[String], message: String
) String:
    id := commit_id(tree, parents, message)
    if r.commits.contains(id):
        return id

    seq := r.order.length() + 1
    r.commits[id.clone()] = Commit(
        tree: tree.clone(), parents: parents.clone(), message: message.clone(), seq: seq
    )
    r.order.append(id.clone())
    return id

fn commit_tree(r: Repo, id: String) Map[String, String]:
    if id == "":
        return Map[String, String]()

    return r.commits[id].tree.clone()

fn new_repo() Repo:
    var branches = Map[String, String]()
    branches["main"] = ""
    return Repo(
        working: Map[String, String](), index: Map[String, String](),
        commits: Map[String, Commit](), order: List[String](), branches: branches,
        tags: Map[String, String](), attached: true, head_branch: "main",
        head_commit: "", conflicts: Set[String](), merging: false, merge_other: "",
        merge_branch: ""
    )

fn head_id(r: Repo) String:
    if r.attached:
        return r.branches.get(r.head_branch).get("")

    return r.head_commit.clone()

fn label_of(r: Repo) String:
    if r.attached:
        return r.head_branch.clone()

    return "detached"

fn move_head(var r: Repo, id: String) Unit:
    if r.attached:
        b := r.head_branch.clone()
        r.branches[b] = id
    else:
        r.head_commit = id

// all commits reachable from start (inclusive) via any parent
fn ancestors(r: Repo, start: String) Set[String]:
    var seen = Set[String]()
    var stack = List[String]()
    if start != "":
        stack.append(start.clone())

    while stack.length() > 0:
        c := stack.pop().get("")
        if seen.contains(c):
            continue

        seen.add(c.clone())
        for p in r.commits[c].parents:
            stack.append(p.clone())

    return seen

// nearest common ancestor with the greatest creation number, or "" if none
fn merge_base(r: Repo, a: String, b: String) String:
    anc_a := ancestors(r, a)
    anc_b := ancestors(r, b)
    var i = r.order.length() - 1

    while i >= 0:
        c := r.order[i].clone()
        if anc_a.contains(c) and anc_b.contains(c):
            return c

        i -= 1

    return ""

// ---------- refs ----------

fn unknown_rev(rev: String) Resolved:
    return Resolved(id: "", err: "unknown revision '{rev}'")

fn resolve(r: Repo, rev: String) Resolved:
    parts := rev.split("~")
    var base = rev.clone()
    var steps = 0

    if parts.length() > 1:
        if parts.length() != 2 or not is_digits(parts[1]):
            return unknown_rev(rev)

        base = parts[0].clone()
        steps = parts[1].parse_int().get(-1)
        if steps < 0:
            return unknown_rev(rev)

    var id = ""
    bc := r.branches.get(base).get("")

    if base == "HEAD":
        id = head_id(r)
    else if bc != "":
        id = bc.clone()
    else if r.tags.contains(base):
        id = r.tags.get(base).get("")
    else if is_hex_prefix(base):
        var matches = 0

        for cid in r.order:
            if cid.starts_with(base):
                matches += 1
                id = cid.clone()

        if matches > 1:
            return Resolved(id: "", err: "ambiguous revision '{rev}'")

    if id == "":
        return unknown_rev(rev)

    var k = 0

    while k < steps:
        ps := r.commits[id].parents
        if ps.length() == 0:
            return unknown_rev(rev)

        id = ps[0].clone()
        k += 1

    return Resolved(id: id, err: "")

// ---------- line diff ----------

fn lcs_table(a: List[String], b: List[String]) List[Int]:
    n := a.length()
    m := b.length()
    w := m + 1
    var t = List[Int]()
    for k in 0..(n + 1) * w:
        t.append(0)

    var i = n - 1

    while i >= 0:
        var j = m - 1

        while j >= 0:
            if a[i] == b[j]:
                t[i * w + j] = t[(i + 1) * w + j + 1] + 1
            else:
                t[i * w + j] = max_int(t[(i + 1) * w + j], t[i * w + j + 1])

            j -= 1

        i -= 1

    return t

// matching pairs as a flat list [i0, j0, i1, j1, ...]
fn matching(a: List[String], b: List[String]) List[Int]:
    n := a.length()
    m := b.length()
    w := m + 1
    t := lcs_table(a, b)
    var pairs = List[Int]()
    var i = 0
    var j = 0

    while i < n and j < m:
        if a[i] == b[j]:
            pairs.append(i)
            pairs.append(j)
            i += 1
            j += 1
        else if t[(i + 1) * w + j] >= t[i * w + j + 1]:
            i += 1
        else:
            j += 1

    return pairs

fn line_diff(a: List[String], b: List[String]) List[String]:
    pairs := matching(a, b)
    var out = List[String]()
    var pi = 0
    var pj = 0
    var k = 0

    while k < pairs.length():
        ai := pairs[k]
        bj := pairs[k + 1]

        while pi < ai:
            out.append("- " + a[pi])
            pi += 1

        while pj < bj:
            out.append("+ " + b[pj])
            pj += 1

        out.append("  " + a[ai])
        pi = ai + 1
        pj = bj + 1
        k += 2

    while pi < a.length():
        out.append("- " + a[pi])
        pi += 1

    while pj < b.length():
        out.append("+ " + b[pj])
        pj += 1

    return out

// ---------- three-way merge ----------

fn resolve_chunk(
    bc: List[String],
    oc: List[String],
    tc: List[String],
    bname: String
) Merged:
    be := enc(bc)
    oe := enc(oc)
    te := enc(tc)
    if oe == be:
        return Merged(text: te, clean: true)
    if te == be:
        return Merged(text: oe, clean: true)
    if oe == te:
        return Merged(text: oe, clean: true)

    return Merged(
        text: "<<<<<<< HEAD\n" + oe + "=======\n" + te + ">>>>>>> " + bname + "\n",
        clean: false
    )

fn merge3(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    bname: String
) Merged:
    bo := matching(base, ours)
    bt := matching(base, theirs)
    nb := base.length()
    var mo = List[Int]()
    var mt = List[Int]()

    for k in 0..nb:
        mo.append(-1)
        mt.append(-1)

    var k = 0

    while k < bo.length():
        mo[bo[k]] = bo[k + 1]
        k += 2

    k = 0

    while k < bt.length():
        mt[bt[k]] = bt[k + 1]
        k += 2

    var text = ""
    var clean = true
    var pb = -1
    var po = -1
    var pt = -1

    for s in 0..nb:
        if mo[s] >= 0 and mt[s] >= 0:
            ch := resolve_chunk(
                sub(base, pb + 1, s), sub(ours, po + 1, mo[s]),
                sub(theirs, pt + 1, mt[s]), bname
            )
            text += ch.text
            if not ch.clean:
                clean = false
            text += base[s] + "\n"
            pb = s
            po = mo[s]
            pt = mt[s]

    last := resolve_chunk(
        sub(base, pb + 1, nb), sub(ours, po + 1, ours.length()),
        sub(theirs, pt + 1, theirs.length()), bname
    )
    text += last.text
    if not last.clean:
        clean = false
    return Merged(text: text, clean: clean)

// ---------- working state helpers ----------

fn is_dirty(r: Repo) Bool:
    ht := commit_tree(r, head_id(r))
    if not maps_equal(r.index, ht):
        return true

    for n in r.index.keys():
        if not r.working.contains(n):
            return true
        if r.working.get(n).get("") != r.index.get(n).get(""):
            return true

    return false

// first name (names sorted) that is untracked in the working tree
fn first_untracked(r: Repo, names: List[String]) String:
    for n in names:
        if (not r.index.contains(n)) and r.working.contains(n):
            return n.clone()
    return ""

// replace the index and working files with target (checkout / fast-forward)
fn apply_tree(var r: Repo, target: Map[String, String]) Unit:
    for n in r.index.keys():
        if r.working.contains(n):
            r.working.remove(n)
    for n in target.keys():
        r.working[n.clone()] = target.get(n).get("")
    r.index = target.clone()

// reset --hard semantics: moves HEAD to target and rewrites index and working files
fn hard_reset(var r: Repo, target: String) Unit:
    old_head := head_id(r)
    var names = r.index.keys()
    for n in commit_tree(r, old_head).keys():
        names.append(n)
    move_head(var r, target.clone())
    for n in names:
        if r.working.contains(n):
            r.working.remove(n)

    tt := commit_tree(r, target)
    for n in tt.keys():
        r.working[n.clone()] = tt.get(n).get("")
    r.index = tt
    r.conflicts = Set[String]()
    r.merging = false
    r.merge_other = ""
    r.merge_branch = ""

fn unmark(var r: Repo, n: String) Unit:
    if r.conflicts.contains(n):
        r.conflicts.remove(n)

fn create_branch(var r: Repo, name: String) Bool:
    if not name_ok(name):
        err_out("invalid branch name '{name}'")
        return false

    if r.branches.contains(name):
        err_out("branch '{name}' already exists")
        return false

    h := head_id(r)

    if h == "":
        err_out("no commits yet")
        return false

    r.branches[name.clone()] = h
    return true

// ---------- commands: working tree ----------

fn cmd_rm(var r: Repo, args: List[String]) Unit:
    if args.length() == 0:
        err_out("usage: rm FILE...")
        return

    for f in args:
        if not r.working.contains(f):
            err_out("no such file: {f}")
            return

        r.working.remove(f)

fn cmd_mv(var r: Repo, args: List[String]) Unit:
    if args.length() != 2:
        err_out("usage: mv OLD NEW")
        return

    old := args[0].clone()
    nw := args[1].clone()

    if not r.working.contains(old):
        err_out("no such file: {old}")
        return

    if old == nw:
        return

    content := r.working.get(old).get("")
    r.working.remove(old)
    r.working[nw] = content

fn cmd_cat(r: Repo, args: List[String]) Unit:
    if args.length() != 1:
        err_out("usage: cat FILE")
        return

    f := args[0].clone()

    if not r.working.contains(f):
        err_out("no such file: {f}")
        return

    for l in dec(r.working.get(f).get("")):
        emit(l)

fn cmd_ls(r: Repo) Unit:
    names := sorted_keys(r.working)

    if names.length() == 0:
        emit("(empty)")
        return

    for n in names:
        emit(n)

fn cmd_add(var r: Repo, args: List[String]) Unit:
    if args.length() == 0:
        err_out("usage: add PATH...")
        return

    for p in args:
        if p == ".":
            for n in sorted_keys(r.working):
                r.index[n.clone()] = r.working.get(n).get("")
                unmark(var r, n)

            for n in sorted_keys(r.index):
                if not r.working.contains(n):
                    r.index.remove(n.clone())
                    unmark(var r, n)
        else if r.working.contains(p):
            r.index[p.clone()] = r.working.get(p).get("")
            unmark(var r, p)
        else if r.index.contains(p):
            r.index.remove(p.clone())
            unmark(var r, p)
        else if r.conflicts.contains(p):
            unmark(var r, p)
        else:
            err_out("pathspec '{p}' did not match any files")
            return

fn print_section(title: String, items: List[String]) Unit:
    if items.length() == 0:
        return

    emit(title)
    for it in items:
        emit("  " + it)

fn cmd_status(r: Repo) Unit:
    if r.attached:
        emit("On branch {r.head_branch}")
    else:
        emit("HEAD detached at {short(r.head_commit)}")

    if r.merging:
        emit("merging: {r.merge_branch}")

    headt := commit_tree(r, head_id(r))
    var staged = List[String]()

    for n in union_names(headt, r.index, Map[String, String]()):
        if r.conflicts.contains(n):
            continue

        inh := headt.contains(n)
        ini := r.index.contains(n)

        if ini and not inh:
            staged.append("new file: {n}")
        else if inh and not ini:
            staged.append("deleted: {n}")
        else if headt.get(n).get("") != r.index.get(n).get(""):
            staged.append("modified: {n}")

    var unstaged = List[String]()

    for n in sorted_keys(r.index):
        if r.conflicts.contains(n):
            continue

        if not r.working.contains(n):
            unstaged.append("deleted: {n}")
        else if r.working.get(n).get("") != r.index.get(n).get(""):
            unstaged.append("modified: {n}")

    var conf = List[String]()
    var cl = r.conflicts.values()
    cl.sort()
    for n in cl:
        conf.append("unmerged: {n}")

    var untracked = List[String]()
    for n in sorted_keys(r.working):
        if (not r.index.contains(n)) and (not r.conflicts.contains(n)):
            untracked.append(n.clone())

    if (
        staged.length() == 0
        and unstaged.length() == 0
        and conf.length() == 0
        and untracked.length() == 0
    ):
        emit("nothing to commit, working tree clean")
        return

    print_section("staged:", staged)
    print_section("unstaged:", unstaged)
    print_section("conflicts:", conf)
    print_section("untracked:", untracked)

// ---------- commands: history ----------

fn cmd_commit(var r: Repo, msg: String) Unit:
    if msg == "":
        err_out("empty commit message")
        return

    if r.conflicts.length() > 0:
        var names = r.conflicts.values()
        names.sort()
        err_out("unresolved conflicts: " + names.join(" "))
        return

    h := head_id(r)

    if r.merging:
        idx := r.index.clone()
        var parents = List[String]()
        parents.append(h.clone())
        parents.append(r.merge_other.clone())

        mid := make_commit(var r, idx, parents, msg)
        move_head(var r, mid.clone())
        r.merging = false
        r.merge_other = ""
        r.merge_branch = ""
        r.conflicts = Set[String]()
        emit("[{label_of(r)} {short(mid)}] {msg}")
        return

    if maps_equal(r.index, commit_tree(r, h)):
        err_out("nothing to commit")
        return

    var parents = List[String]()
    if h != "":
        parents.append(h.clone())

    idx := r.index.clone()
    id := make_commit(var r, idx, parents, msg)
    move_head(var r, id.clone())

    if h == "":
        emit("[{label_of(r)} (root-commit) {short(id)}] {msg}")
    else:
        emit("[{label_of(r)} {short(id)}] {msg}")

fn cmd_log(r: Repo, args: List[String]) Unit:
    var limit = -1

    if args.length() != 0:
        if args.length() == 2 and args[0] == "-n" and is_digits(args[1]):
            limit = args[1].parse_int().get(-1)

        if limit < 0:
            err_out("usage: log [-n N]")
            return

    h := head_id(r)

    if h == "":
        err_out("no commits yet")
        return

    reach := ancestors(r, h)
    var printed = 0
    var i = r.order.length() - 1

    while i >= 0:
        if limit >= 0 and printed >= limit:
            break

        c := r.order[i].clone()

        if reach.contains(c):
            cm := r.commits[c]
            var line = short(c) + " " + cm.message
            if cm.parents.length() == 2:
                line += " (merge {short(cm.parents[0])} {short(cm.parents[1])})"
            emit(line)
            printed += 1

        i -= 1

fn cmd_show(r: Repo, args: List[String]) Unit:
    if args.length() != 1:
        err_out("usage: show REF")
        return

    res := resolve(r, args[0])

    if res.err != "":
        err_out(res.err)
        return

    id := res.id.clone()
    cm := r.commits[id]
    emit("commit {id}")
    emit("tree {tree_hash(cm.tree)}")
    for p in cm.parents:
        emit("parent {p}")
    emit("message: {cm.message}")
    emit("files:")
    for n in sorted_keys(cm.tree):
        emit("  {n} {short(hex16(hash_text(cm.tree.get(n).get(""))))}")

fn cmd_diff(r: Repo, args: List[String]) Unit:
    if args.length() > 2:
        err_out("usage: diff [REF [REF]]")
        return

    var left = Map[String, String]()
    var right = Map[String, String]()

    if args.length() == 0:
        left = r.index.clone()
        right = r.working.clone()
    else if args.length() == 1:
        res := resolve(r, args[0])

        if res.err != "":
            err_out(res.err)
            return

        left = commit_tree(r, res.id)
        right = r.working.clone()
    else:
        r1 := resolve(r, args[0])

        if r1.err != "":
            err_out(r1.err)
            return

        r2 := resolve(r, args[1])

        if r2.err != "":
            err_out(r2.err)
            return

        left = commit_tree(r, r1.id)
        right = commit_tree(r, r2.id)

    var any = false

    for n in union_names(left, right, Map[String, String]()):
        lp := left.contains(n)
        rp := right.contains(n)
        lc := left.get(n).get("")
        rc := right.get(n).get("")
        if lp == rp and lc == rc:
            continue

        any = true
        emit("diff {n}")
        if not lp:
            emit("new file")
        if not rp:
            emit("deleted file")
        for l in line_diff(dec(lc), dec(rc)):
            emit(l)

    if not any:
        emit("(no differences)")

fn cmd_branch(var r: Repo, args: List[String]) Unit:
    if args.length() == 0:
        if not r.attached:
            emit("* (HEAD detached at {short(r.head_commit)})")

        for n in sorted_keys(r.branches):
            if r.attached and n == r.head_branch:
                emit("* {n}")
            else:
                emit("  {n}")

        return

    if args.length() == 1:
        _created := create_branch(var r, args[0].clone())
        return

    if args.length() == 2 and args[0] == "-d":
        name := args[1].clone()

        if not r.branches.contains(name):
            err_out("branch '{name}' not found")
            return

        if r.attached and r.head_branch == name:
            err_out("cannot delete the current branch '{name}'")
            return

        c := r.branches.get(name).get("")
        h := head_id(r)

        if c == "" or h == "" or not ancestors(r, h).contains(c):
            err_out("branch '{name}' is not fully merged")
            return

        r.branches.remove(name.clone())
        emit("Deleted branch {name} (was {short(c)}).")
        return

    err_out("usage: branch [NAME | -d NAME]")

fn cmd_tag(var r: Repo, args: List[String]) Unit:
    if args.length() == 0:
        for n in sorted_keys(r.tags):
            emit(n)
        return

    if args.length() > 2:
        err_out("usage: tag [NAME [REF]]")
        return

    name := args[0].clone()

    if not name_ok(name):
        err_out("invalid tag name '{name}'")
        return

    if r.tags.contains(name):
        err_out("tag '{name}' already exists")
        return

    var rev = "HEAD"
    if args.length() == 2:
        rev = args[1].clone()

    if rev == "HEAD" and head_id(r) == "":
        err_out("no commits yet")
        return

    res := resolve(r, rev)

    if res.err != "":
        err_out(res.err)
        return

    r.tags[name] = res.id

fn check_switch(r: Repo, target: Map[String, String]) Bool:
    if is_dirty(r):
        err_out("local changes would be overwritten")
        return false

    bad := first_untracked(r, sorted_keys(target))

    if bad != "":
        err_out("untracked file would be overwritten: {bad}")
        return false

    return true

fn cmd_checkout(var r: Repo, args: List[String]) Unit:
    if args.length() == 2 and args[0] == "-b":
        name := args[1].clone()
        created := create_branch(var r, name.clone())

        if created:
            r.attached = true
            r.head_branch = name.clone()
            emit("Switched to a new branch '{name}'")

        return

    if args.length() != 1:
        err_out("usage: checkout REF | checkout -b NAME")
        return

    if r.merging:
        err_out("merge in progress")
        return

    target := args[0].clone()

    if r.branches.contains(target):
        if r.attached and r.head_branch == target:
            emit("Already on '{target}'")
            return

        tt := commit_tree(r, r.branches.get(target).get(""))
        if not check_switch(r, tt):
            return

        apply_tree(var r, tt)
        r.attached = true
        r.head_branch = target.clone()
        emit("Switched to branch '{target}'")
        return

    res := resolve(r, target)

    if res.err != "":
        err_out(res.err)
        return

    tt := commit_tree(r, res.id)
    if not check_switch(r, tt):
        return

    apply_tree(var r, tt)
    r.attached = false
    r.head_commit = res.id.clone()

    cm := r.commits[res.id]
    emit("HEAD is now at {short(res.id)} {cm.message}")

fn cmd_reset(var r: Repo, args: List[String]) Unit:
    if args.length() == 0 or args.length() > 2 or args[0] != "--hard":
        err_out("usage: reset --hard [REF]")
        return

    var target = head_id(r)

    if args.length() == 2:
        res := resolve(r, args[1])

        if res.err != "":
            err_out(res.err)
            return

        target = res.id.clone()
    else if target == "":
        err_out("no commits yet")
        return

    hard_reset(var r, target.clone())

    cm := r.commits[target]
    emit("HEAD is now at {short(target)} {cm.message}")

fn cmd_merge(var r: Repo, args: List[String]) Unit:
    if args.length() == 1 and args[0] == "--abort":
        if not r.merging:
            err_out("no merge in progress")
            return

        h := head_id(r)
        hard_reset(var r, h)
        emit("Merge aborted.")
        return

    if args.length() != 1:
        err_out("usage: merge BRANCH")
        return

    bname := args[0].clone()

    if r.merging:
        err_out("merge in progress")
        return

    cur := head_id(r)

    if cur == "":
        err_out("no commits yet")
        return

    if not r.branches.contains(bname) or r.branches.get(bname).get("") == "":
        err_out("unknown branch '{bname}'")
        return

    other := r.branches.get(bname).get("")

    if is_dirty(r):
        err_out("local changes would be overwritten")
        return

    if ancestors(r, cur).contains(other):
        emit("Already up to date.")
        return

    if ancestors(r, other).contains(cur):
        ot := commit_tree(r, other)
        bad := first_untracked(r, sorted_keys(ot))

        if bad != "":
            err_out("untracked file would be overwritten: {bad}")
            return

        apply_tree(var r, ot)
        move_head(var r, other.clone())
        emit("Fast-forward")
        return

    base := merge_base(r, cur, other)
    bt := commit_tree(r, base)
    ot := commit_tree(r, cur)
    tt := commit_tree(r, other)
    var result = Map[String, String]()
    var work = Map[String, String]()
    var kinds = Map[String, String]()
    var conflicted = Set[String]()

    for n in union_names(bt, ot, tt):
        bp := bt.contains(n)
        op := ot.contains(n)
        tp := tt.contains(n)
        bc := bt.get(n).get("")
        oc := ot.get(n).get("")
        tc := tt.get(n).get("")

        if op == tp and oc == tc:
            if op:
                result[n.clone()] = oc.clone()
        else if op == bp and oc == bc:
            if tp:
                result[n.clone()] = tc.clone()
        else if tp == bp and tc == bc:
            if op:
                result[n.clone()] = oc.clone()
        else if op != tp:
            conflicted.add(n.clone())
            kinds[n.clone()] = "modify/delete"

            if op:
                result[n.clone()] = oc.clone()
                work[n.clone()] = oc.clone()
            else:
                work[n.clone()] = tc.clone()
        else:
            m := merge3(dec(bc), dec(oc), dec(tc), bname)

            if m.clean:
                result[n.clone()] = m.text.clone()
            else:
                conflicted.add(n.clone())

                if bp:
                    kinds[n.clone()] = "content"
                else:
                    kinds[n.clone()] = "add/add"

                result[n.clone()] = oc.clone()
                work[n.clone()] = m.text.clone()

    for n in result.keys():
        if not work.contains(n):
            work[n.clone()] = result.get(n).get("")

    touched := union_names(result, work, Map[String, String]())
    bad := first_untracked(r, touched)

    if bad != "":
        err_out("untracked file would be overwritten: {bad}")
        return

    for n in sorted_keys(r.index):
        if not result.contains(n) and r.working.contains(n):
            r.working.remove(n)
    for n in work.keys():
        r.working[n.clone()] = work.get(n).get("")
    r.index = result.clone()

    if conflicted.length() == 0:
        var parents = List[String]()
        parents.append(cur.clone())
        parents.append(other.clone())

        msg := "Merge branch '{bname}'"
        mid := make_commit(var r, result, parents, msg.clone())
        move_head(var r, mid.clone())
        emit("Merge made by the 'three-way' strategy.")
        emit("[{label_of(r)} {short(mid)}] {msg}")
        return

    r.merging = true
    r.merge_other = other.clone()
    r.merge_branch = bname.clone()

    var cn = conflicted.values()
    cn.sort()
    r.conflicts = conflicted

    for n in cn:
        kind := kinds.get(n).get("")

        if kind == "modify/delete":
            emit("CONFLICT (modify/delete): {n}")
        else:
            emit("CONFLICT ({kind}): Merge conflict in {n}")

    emit("Automatic merge failed; fix conflicts and then commit the result.")

// ---------- entry point ----------

export fn main() Int:
    input := read_input().get()
    var r = new_repo()
    total := input.length()
    var i = 0

    while i < total:
        line := input[i].clone()
        i += 1

        t := line.trim()
        if t == "" or t.starts_with("#"):
            continue

        emit("> " + line.trim_end())

        parts := t.fields()
        cmd := parts[0].clone()
        var args = List[String]()
        for k in 1..parts.length():
            args.append(parts[k].clone())

        if cmd == "write" or cmd == "append":
            if args.length() != 1:
                err_out("usage: {cmd} FILE")
                continue

            var content = ""

            while i < total and input[i] != ".":
                content += input[i] + "\n"
                i += 1

            if i < total:
                i += 1

            f := args[0].clone()

            if cmd == "write":
                r.working[f] = content
            else:
                old := r.working.get(f).get("")
                r.working[f] = old + content
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
            msg := t.slice(6, t.length()).get().trim()
            cmd_commit(var r, msg)
        else if cmd == "log":
            cmd_log(r, args)
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
        else if cmd == "merge":
            cmd_merge(var r, args)
        else if cmd == "reset":
            cmd_reset(var r, args)
        else:
            err_out("unknown command '{cmd}'")

    return 0
