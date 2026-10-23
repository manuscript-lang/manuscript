import {stdout, stdin, read_line} from "@std/io.ms"
import {range} from "@std/collections.ms"
import {bit_xor, bit_and, wrapping_multiply, shift_right_unsigned} from "@std/bits.ms"

let DIGITS = "0123456789"
let HEX = "0123456789abcdef"
let NAME_START = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/"
let NAME_REST = NAME_START + "-"
let FNV_OFFSET = -3750763034362895579
let FNV_PRIME = 1099511628211

type Fail:
    msg: String

impl Error for Fail:
    fn message() String:
        return self.msg

type Commit:
    id: String
    number: Int
    tree: Map[String, String]
    parents: List[String]
    message: String

type Repo:
    files: Map[String, String]
    index: Map[String, String]
    commits: Map[String, Commit]
    branches: Map[String, String]
    tags: Map[String, String]
    head_branch: String
    detached: String
    merging: Bool
    merge_other: String
    merge_branch: String
    conflicts: Set[String]

type Pairs:
    left: List[Int]
    right: List[Int]

type Merged:
    lines: List[String]
    clean: Bool

type Plan:
    work: Map[String, String]
    index: Map[String, String]
    kinds: Map[String, String]

fn fail[T](msg: String) Result[T, Fail]:
    return error(Fail(msg: msg))

fn say(text: String) Unit:
    stdout().write("{text}\n").get()

fn report(cause: Fail) Unit:
    say("error: {cause.msg}")

fn fnv(text: String) Int:
    var h = FNV_OFFSET
    for b in text.to_bytes().values():
        h = wrapping_multiply(bit_xor(h, b), FNV_PRIME)
    return h

fn hex16(h: Int) String:
    var out = ""
    for i in range(0, 16):
        out = out + HEX.get(bit_and(shift_right_unsigned(h, (15 - i) * 4), 15))
    return out

fn short(id: String) String:
    return id.slice(0, 7).get()

fn compare_text(left: String, right: String) Int:
    return left.compare(right)

fn sorted_keys(tree: Map[String, String]) List[String]:
    return tree.keys().sorted(compare_text)

fn text_of(lines: List[String]) String:
    var text = ""
    for line in lines:
        text = text + line + "\n"
    return text

fn lines_of(content: String) List[String]:
    if content == "":
        return []

    return content.slice(0, -1).get().split("\n")

fn same_lines(left: List[String], right: List[String]) Bool:
    if left.length() != right.length():
        return false

    for k in range(0, left.length()):
        if left.get(k) != right.get(k):
            return false
    return true

fn same_tree(left: Map[String, String], right: Map[String, String]) Bool:
    if left.length() != right.length():
        return false

    for name in left.keys():
        if not right.contains(name) or left.get_or(name, "") != right.get_or(name, ""):
            return false
    return true

fn tree_hash(tree: Map[String, String]) String:
    var text = ""
    for name in sorted_keys(tree):
        text = text + "{name} {hex16(fnv(tree.get_or(name, "")))}\n"
    return hex16(fnv(text))

fn commit_id(tree: Map[String, String], parents: List[String], message: String) String:
    var text = "tree {tree_hash(tree)}\n"
    for parent in parents:
        text = text + "parent {parent}\n"
    return hex16(fnv(text + "\n" + message + "\n"))

fn new_repo() Repo:
    var branches = Map[String, String]()
    branches.add("main", "")
    return Repo(
        files: Map[String, String](), index: Map[String, String](),
        commits: Map[String, Commit](), branches: branches, tags: Map[String, String](),
        head_branch: "main", detached: "", merging: false, merge_other: "",
        merge_branch: "", conflicts: Set[String]()
    )

fn head_commit(repo: Repo) String:
    if repo.head_branch == "":
        return repo.detached

    return repo.branches.get_or(repo.head_branch, "")

fn label(repo: Repo) String:
    if repo.head_branch == "":
        return "detached"

    return repo.head_branch

fn tree_of(repo: Repo, id: String) Map[String, String]:
    if id == "":
        return Map[String, String]()

    return repo.commits.get(id).get().tree.clone()

fn head_tree(repo: Repo) Map[String, String]:
    return tree_of(repo, head_commit(repo))

fn move_head(var repo: Repo, id: String) Unit:
    if repo.head_branch == "":
        repo.detached = id
    else:
        repo.branches.add(repo.head_branch, id)

fn make_commit(
    var repo: Repo, tree: Map[String, String], parents: List[String], message: String
) String:
    let id = commit_id(tree.clone(), parents.clone(), message)

    if not repo.commits.contains(id):
        let number = repo.commits.length() + 1
        let commit = Commit(
            id: id, number: number, tree: tree.clone(), parents: parents.clone(),
            message: message
        )
        repo.commits.add(id, commit)

    return id

fn ancestors(repo: Repo, id: String) Set[String]:
    var seen = Set[String]()
    var todo: List[String] = [id]
    var k = 0

    while k < todo.length():
        let current = todo.get(k)
        k += 1

        if not seen.contains(current):
            seen.add(current)
            for parent in repo.commits.get(current).get().parents:
                todo.append(parent)

    return seen

fn is_ancestor(repo: Repo, ancestor: String, descendant: String) Bool:
    return ancestors(repo, descendant).contains(ancestor)

fn merge_base(repo: Repo, left: String, right: String) String:
    let right_set = ancestors(repo, right)
    var best = ""
    var best_number = 0

    for id in ancestors(repo, left).values():
        if right_set.contains(id):
            let number = repo.commits.get(id).get().number

            if number > best_number:
                best = id
                best_number = number

    return best

fn parse_count(text: String) Int:
    if text == "":
        return -1

    for c in text.chars():
        if not DIGITS.contains(c):
            return -1
    return text.parse_int().get(-1)

fn valid_name(name: String) Bool:
    let chars = name.chars()
    if chars.length() == 0:
        return false
    if not NAME_START.contains(chars.get(0)):
        return false

    for k in range(1, chars.length()):
        if not NAME_REST.contains(chars.get(k)):
            return false
    return true

fn resolve_prefix(repo: Repo, base: String, text: String) Result[String, Fail]:
    let chars = base.chars()
    if chars.length() < 4:
        return fail("unknown revision '{text}'")

    for c in chars:
        if not HEX.contains(c):
            return fail("unknown revision '{text}'")

    var found = ""
    var count = 0

    for id in repo.commits.keys():
        if id.starts_with(base):
            found = id
            count += 1

    if count == 0:
        return fail("unknown revision '{text}'")
    if count > 1:
        return fail("ambiguous revision '{text}'")

    return ok(found)

fn resolve(repo: Repo, text: String) Result[String, Fail]:
    let parts = text.split("~")
    if parts.length() > 2:
        return fail("unknown revision '{text}'")

    var base = text
    var steps = 0

    if parts.length() == 2:
        base = parts.get(0)
        steps = parse_count(parts.get(1))
        if steps < 0:
            return fail("unknown revision '{text}'")

    var id = ""

    if base == "HEAD":
        id = head_commit(repo)
    else:
        id = repo.branches.get_or(base, "")
        if id == "":
            id = repo.tags.get_or(base, "")
        if id == "":
            return resolve_prefix(repo, base, text)

    if id == "":
        return fail("unknown revision '{text}'")

    for k in range(0, steps):
        let parents = repo.commits.get(id).get().parents
        if parents.length() == 0:
            return fail("unknown revision '{text}'")

        id = parents.get(0)

    return ok(id)

fn is_dirty(repo: Repo) Bool:
    if not same_tree(repo.index, head_tree(repo)):
        return true

    for name in repo.index.keys():
        if (
            not repo.files.contains(name)
            or repo.files.get_or(name, "") != repo.index.get_or(name, "")
        ):
            return true
    return false

fn untracked_check(repo: Repo, names: List[String]) Result[Unit, Fail]:
    for name in names.sorted(compare_text):
        if repo.files.contains(name) and not repo.index.contains(name):
            return fail("untracked file would be overwritten: {name}")
    return ok(nop())

fn check_switch(repo: Repo, target: Map[String, String]) Result[Unit, Fail]:
    if is_dirty(repo):
        return fail("local changes would be overwritten")

    return untracked_check(repo, sorted_keys(target))

# Manuscript has no Unit literal; nop() supplies one for ok(...) results.
fn nop() Unit:
    return

fn apply_state(
    var repo: Repo, work: Map[String, String], index: Map[String, String],
    old_head: Map[String, String]
) Unit:
    var stale: List[String] = []
    for name in repo.index.keys():
        stale.append(name)
    for name in old_head.keys():
        stale.append(name)
    for name in stale:
        if repo.files.contains(name):
            repo.files.remove(name)
    for name in work.keys():
        repo.files.add(name, work.get_or(name, ""))
    repo.index = index.clone()

fn reset_hard(var repo: Repo, id: String) Unit:
    let old_head = head_tree(repo)
    let target = tree_of(repo, id)
    apply_state(var repo, target, target.clone(), old_head)
    repo.conflicts.clear()
    repo.merging = false
    repo.merge_other = ""
    repo.merge_branch = ""
    move_head(var repo, id)

fn message_of(repo: Repo, id: String) String:
    return repo.commits.get(id).get().message

fn matching(left: List[String], right: List[String]) Pairs:
    let n = left.length()
    let m = right.length()
    let width = m + 1
    var table: List[Int] = []
    for k in range(0, (n + 1) * width):
        table.append(0)

    var i = n - 1

    while i >= 0:
        var j = m - 1

        while j >= 0:
            if left.get(i) == right.get(j):
                table.set(i * width + j, 1 + table.get((i + 1) * width + j + 1))
            else:
                let down = table.get((i + 1) * width + j)
                let across = table.get(i * width + j + 1)

                if down >= across:
                    table.set(i * width + j, down)
                else:
                    table.set(i * width + j, across)

            j -= 1

        i -= 1

    var pairs = Pairs(left: [], right: [])
    var a = 0
    var b = 0

    while a < n and b < m:
        if left.get(a) == right.get(b):
            pairs.left.append(a)
            pairs.right.append(b)
            a += 1
            b += 1
        else:
            if table.get((a + 1) * width + b) >= table.get(a * width + b + 1):
                a += 1
            else:
                b += 1

    return pairs

fn line_diff(left: List[String], right: List[String]) List[String]:
    let pairs = matching(left, right)
    var out: List[String] = []
    var li = 0
    var ri = 0

    for k in range(0, pairs.left.length()):
        let pl = pairs.left.get(k)
        let pr = pairs.right.get(k)

        while li < pl:
            out.append("- " + left.get(li))
            li += 1

        while ri < pr:
            out.append("+ " + right.get(ri))
            ri += 1

        out.append("  " + left.get(pl))
        li = pl + 1
        ri = pr + 1

    while li < left.length():
        out.append("- " + left.get(li))
        li += 1

    while ri < right.length():
        out.append("+ " + right.get(ri))
        ri += 1

    return out

fn sub_lines(lines: List[String], start: Int, end: Int) List[String]:
    return lines.slice(start, end).get()

fn append_all(var out: List[String], chunk: List[String]) Unit:
    for line in chunk:
        out.append(line)

fn merge_lines(
    base: List[String],
    ours: List[String],
    theirs: List[String],
    branch: String
) Merged:
    let po = matching(base, ours)
    let pt = matching(base, theirs)
    var ours_of: List[Int] = []
    var theirs_of: List[Int] = []

    for k in range(0, base.length()):
        ours_of.append(-1)
        theirs_of.append(-1)

    for k in range(0, po.left.length()):
        ours_of.set(po.left.get(k), po.right.get(k))
    for k in range(0, pt.left.length()):
        theirs_of.set(pt.left.get(k), pt.right.get(k))

    var stable_base: List[Int] = []
    var stable_ours: List[Int] = []
    var stable_theirs: List[Int] = []

    for b in range(0, base.length()):
        if ours_of.get(b) >= 0 and theirs_of.get(b) >= 0:
            stable_base.append(b)
            stable_ours.append(ours_of.get(b))
            stable_theirs.append(theirs_of.get(b))

    stable_base.append(base.length())
    stable_ours.append(ours.length())
    stable_theirs.append(theirs.length())

    var out: List[String] = []
    var clean = true
    var prev_base = -1
    var prev_ours = -1
    var prev_theirs = -1

    for k in range(0, stable_base.length()):
        let bi = stable_base.get(k)
        let oi = stable_ours.get(k)
        let ti = stable_theirs.get(k)
        let base_chunk = sub_lines(base, prev_base + 1, bi)
        let ours_chunk = sub_lines(ours, prev_ours + 1, oi)
        let theirs_chunk = sub_lines(theirs, prev_theirs + 1, ti)

        if same_lines(ours_chunk, base_chunk):
            append_all(var out, theirs_chunk)
        else:
            if same_lines(theirs_chunk, base_chunk):
                append_all(var out, ours_chunk)
            else:
                if same_lines(ours_chunk, theirs_chunk):
                    append_all(var out, ours_chunk)
                else:
                    clean = false
                    out.append("<<<<<<< HEAD")
                    append_all(var out, ours_chunk)
                    out.append("=======")
                    append_all(var out, theirs_chunk)
                    out.append(">>>>>>> " + branch)

        if k < stable_base.length() - 1:
            out.append(base.get(bi))
        prev_base = bi
        prev_ours = oi
        prev_theirs = ti

    return Merged(lines: out, clean: clean)

fn put(var tree: Map[String, String], name: String, present: Bool, text: String) Unit:
    if present:
        tree.add(name, text)

fn plan_merge(
    base: Map[String, String],
    ours: Map[String, String],
    theirs: Map[String, String],
    branch: String
) Plan:
    var names = Set[String]()
    for name in base.keys():
        names.add(name)
    for name in ours.keys():
        names.add(name)
    for name in theirs.keys():
        names.add(name)

    var work = Map[String, String]()
    var index = Map[String, String]()
    var kinds = Map[String, String]()

    for name in names.values().sorted(compare_text):
        let in_base = base.contains(name)
        let base_text = base.get_or(name, "")
        let in_ours = ours.contains(name)
        let ours_text = ours.get_or(name, "")
        let in_theirs = theirs.contains(name)
        let theirs_text = theirs.get_or(name, "")
        let choice = choose(
            in_base, base_text, in_ours, ours_text, in_theirs, theirs_text
        )

        if choice == 0:
            put(var work, name, in_ours, ours_text)
            put(var index, name, in_ours, ours_text)

        if choice == 1:
            put(var work, name, in_theirs, theirs_text)
            put(var index, name, in_theirs, theirs_text)

        if choice == 2:
            if in_ours != in_theirs:
                kinds.add(name, "modify/delete")

                if in_ours:
                    put(var work, name, true, ours_text)
                else:
                    put(var work, name, true, theirs_text)

                put(var index, name, in_ours, ours_text)
            else:
                let merged = merge_lines(
                    lines_of(base_text), lines_of(ours_text), lines_of(theirs_text),
                    branch
                )
                let merged_text = text_of(merged.lines.clone())
                put(var work, name, true, merged_text)

                if merged.clean:
                    put(var index, name, true, merged_text)
                else:
                    if in_base:
                        kinds.add(name, "content")
                    else:
                        kinds.add(name, "add/add")

                    put(var index, name, true, ours_text)

    return Plan(work: work, index: index, kinds: kinds)

fn choose(
    in_base: Bool,
    base_text: String,
    in_ours: Bool,
    ours_text: String,
    in_theirs: Bool,
    theirs_text: String
) Int:
    if in_ours == in_theirs and ours_text == theirs_text:
        return 0
    if in_ours == in_base and ours_text == base_text:
        return 1
    if in_theirs == in_base and theirs_text == base_text:
        return 0

    return 2

fn cmd_write(var repo: Repo, args: List[String], block: List[String], append: Bool) Result[
    Unit, Fail
]:
    if args.length() != 1:
        if append:
            return fail("usage: append FILE")

        return fail("usage: write FILE")

    let name = args.get(0)
    var content = text_of(block)
    if append:
        content = repo.files.get_or(name, "") + content
    repo.files.add(name, content)
    return ok(nop())

fn cmd_rm(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 0:
        return fail("usage: rm FILE...")

    for name in args:
        if not repo.files.contains(name):
            return fail("no such file: {name}")

        repo.files.remove(name)

    return ok(nop())

fn cmd_mv(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() != 2:
        return fail("usage: mv OLD NEW")

    let old_name = args.get(0)
    let new_name = args.get(1)
    if not repo.files.contains(old_name):
        return fail("no such file: {old_name}")

    let content = repo.files.get_or(old_name, "")
    repo.files.remove(old_name)
    repo.files.add(new_name, content)
    return ok(nop())

fn cmd_cat(repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() != 1:
        return fail("usage: cat FILE")

    let name = args.get(0)
    if not repo.files.contains(name):
        return fail("no such file: {name}")

    for line in lines_of(repo.files.get_or(name, "")):
        say(line)
    return ok(nop())

fn cmd_ls(repo: Repo) Result[Unit, Fail]:
    if repo.files.length() == 0:
        say("(empty)")
    for name in sorted_keys(repo.files):
        say(name)
    return ok(nop())

fn cmd_add(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 0:
        return fail("usage: add PATH...")

    for path in args:
        if path == ".":
            for name in repo.files.keys():
                repo.index.add(name, repo.files.get_or(name, ""))
                repo.conflicts.remove(name)

            var gone: List[String] = []
            for name in repo.index.keys():
                if not repo.files.contains(name):
                    gone.append(name)

            for name in gone:
                repo.index.remove(name)
                repo.conflicts.remove(name)
        else:
            if repo.files.contains(path):
                repo.index.add(path, repo.files.get_or(path, ""))
                repo.conflicts.remove(path)
            else:
                if repo.index.contains(path):
                    repo.index.remove(path)
                    repo.conflicts.remove(path)
                else:
                    if repo.conflicts.contains(path):
                        repo.conflicts.remove(path)
                    else:
                        return fail("pathspec '{path}' did not match any files")

    return ok(nop())

fn print_section(title: String, items: List[String]) Unit:
    if items.length() == 0:
        return

    say(title)
    for item in items:
        say("  " + item)

fn cmd_status(repo: Repo) Result[Unit, Fail]:
    if repo.head_branch == "":
        say("HEAD detached at {short(repo.detached)}")
    else:
        say("On branch {repo.head_branch}")

    if repo.merging:
        say("merging: {repo.merge_branch}")

    let head = head_tree(repo)
    var names = Set[String]()
    for name in head.keys():
        names.add(name)
    for name in repo.index.keys():
        names.add(name)

    var staged: List[String] = []

    for name in names.values().sorted(compare_text):
        if not repo.conflicts.contains(name):
            let in_index = repo.index.contains(name)
            let in_head = head.contains(name)

            if in_index and not in_head:
                staged.append("new file: {name}")
            else:
                if in_head and not in_index:
                    staged.append("deleted: {name}")
                else:
                    if repo.index.get_or(name, "") != head.get_or(name, ""):
                        staged.append("modified: {name}")

    var unstaged: List[String] = []

    for name in sorted_keys(repo.index):
        if not repo.conflicts.contains(name):
            if not repo.files.contains(name):
                unstaged.append("deleted: {name}")
            else:
                if repo.files.get_or(name, "") != repo.index.get_or(name, ""):
                    unstaged.append("modified: {name}")

    var conflicted: List[String] = []
    for name in repo.conflicts.values().sorted(compare_text):
        conflicted.append("unmerged: {name}")

    var untracked: List[String] = []
    for name in sorted_keys(repo.files):
        if not repo.index.contains(name) and not repo.conflicts.contains(name):
            untracked.append(name)

    if (
        staged.length() + unstaged.length() + conflicted.length() + untracked.length() == 0
    ):
        say("nothing to commit, working tree clean")
        return ok(nop())

    print_section("staged:", staged)
    print_section("unstaged:", unstaged)
    print_section("conflicts:", conflicted)
    print_section("untracked:", untracked)
    return ok(nop())

fn text_after_word(raw: String) String:
    let chars = raw.trim_start().chars()
    var k = 0
    while k < chars.length() and not is_space(chars.get(k)):
        k += 1
    return chars.slice(k, chars.length()).get().join("").trim()

fn is_space(c: String) Bool:
    return c == " " or c == "\t" or c == "\r"

fn split_words(text: String) List[String]:
    var words: List[String] = []
    var current = ""

    for c in text.chars():
        if is_space(c):
            if current != "":
                words.append(current)
                current = ""
        else:
            current = current + c

    if current != "":
        words.append(current)
    return words

fn cmd_commit(var repo: Repo, message: String) Result[Unit, Fail]:
    if message == "":
        return fail("empty commit message")
    if repo.conflicts.length() > 0:
        return fail(
            "unresolved conflicts: " + repo.conflicts.values().sorted(
                compare_text
            ).join(" ")
        )

    let head = head_commit(repo)
    var parents: List[String] = []

    if repo.merging:
        parents.append(head)
        parents.append(repo.merge_other)
    else:
        if same_tree(repo.index, head_tree(repo)):
            return fail("nothing to commit")

        if head != "":
            parents.append(head)

    let root_note = if_root(parents.length())
    let id = make_commit(var repo, repo.index.clone(), parents, message)
    move_head(var repo, id)

    if repo.merging:
        repo.merging = false
        repo.merge_other = ""
        repo.merge_branch = ""

    say("[{label(repo)}{root_note} {short(id)}] {message}")
    return ok(nop())

fn if_root(parent_count: Int) String:
    if parent_count == 0:
        return " (root-commit)"

    return ""

fn by_number_desc(left: Commit, right: Commit) Int:
    return right.number - left.number

fn cmd_log(repo: Repo, args: List[String]) Result[Unit, Fail]:
    var limit = -1

    if args.length() == 2 and args.get(0) == "-n":
        let parsed = parse_count(args.get(1))
        if parsed < 0:
            return fail("usage: log [-n N]")

        limit = parsed
    else:
        if args.length() != 0:
            return fail("usage: log [-n N]")

    let head = head_commit(repo)
    if head == "":
        return fail("no commits yet")

    var listed: List[Commit] = []
    for id in ancestors(repo, head).values():
        listed.append(repo.commits.get(id).get())

    var shown = 0

    for c in listed.sorted(by_number_desc):
        if limit >= 0 and shown >= limit:
            break

        var line = "{short(c.id)} {c.message}"
        if c.parents.length() == 2:
            line = line + " (merge {short(c.parents.get(0))} {short(c.parents.get(1))})"
        say(line)
        shown += 1

    return ok(nop())

fn cmd_diff(repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() > 2:
        return fail("usage: diff [REF [REF]]")

    var left = repo.index.clone()
    var right = repo.files.clone()

    if args.length() >= 1:
        let left_id = try resolve(repo, args.get(0))
        left = tree_of(repo, left_id)

    if args.length() == 2:
        let right_id = try resolve(repo, args.get(1))
        right = tree_of(repo, right_id)

    var names = Set[String]()
    for name in left.keys():
        names.add(name)
    for name in right.keys():
        names.add(name)

    var any = false

    for name in names.values().sorted(compare_text):
        let in_left = left.contains(name)
        let in_right = right.contains(name)
        let left_text = left.get_or(name, "")
        let right_text = right.get_or(name, "")

        if in_left != in_right or left_text != right_text:
            any = true
            say("diff {name}")
            if not in_left:
                say("new file")
            if not in_right:
                say("deleted file")
            for line in line_diff(lines_of(left_text), lines_of(right_text)):
                say(line)

    if not any:
        say("(no differences)")
    return ok(nop())

fn create_branch(var repo: Repo, name: String) Result[Unit, Fail]:
    if not valid_name(name):
        return fail("invalid branch name '{name}'")
    if repo.branches.contains(name):
        return fail("branch '{name}' already exists")

    let head = head_commit(repo)
    if head == "":
        return fail("no commits yet")

    repo.branches.add(name, head)
    return ok(nop())

fn cmd_branch(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 0:
        if repo.head_branch == "":
            say("* (HEAD detached at {short(repo.detached)})")

        for name in sorted_keys(repo.branches):
            if name == repo.head_branch:
                say("* {name}")
            else:
                say("  {name}")

        return ok(nop())

    if args.length() == 2 and args.get(0) == "-d":
        let name = args.get(1)
        if not repo.branches.contains(name):
            return fail("branch '{name}' not found")
        if repo.head_branch == name:
            return fail("cannot delete the current branch '{name}'")

        let target = repo.branches.get_or(name, "")
        if target != "" and not is_ancestor(repo, target, head_commit(repo)):
            return fail("branch '{name}' is not fully merged")

        repo.branches.remove(name)

        if target == "":
            say("Deleted branch {name} (was unborn).")
        else:
            say("Deleted branch {name} (was {short(target)}).")

        return ok(nop())

    if args.length() == 1:
        return create_branch(var repo, args.get(0))

    return fail("usage: branch [NAME | -d NAME]")

fn cmd_tag(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 0:
        for name in sorted_keys(repo.tags):
            say(name)
        return ok(nop())

    if args.length() > 2:
        return fail("usage: tag [NAME [REF]]")

    let name = args.get(0)
    if not valid_name(name):
        return fail("invalid tag name '{name}'")
    if repo.tags.contains(name):
        return fail("tag '{name}' already exists")

    var target_ref = "HEAD"
    if args.length() == 2:
        target_ref = args.get(1)
    if target_ref == "HEAD" and head_commit(repo) == "":
        return fail("no commits yet")

    let id = try resolve(repo, target_ref)
    repo.tags.add(name, id)
    return ok(nop())

fn cmd_show(repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() != 1:
        return fail("usage: show REF")

    let id = try resolve(repo, args.get(0))
    let c = repo.commits.get(id).get()
    say("commit {id}")
    say("tree {tree_hash(c.tree)}")
    for parent in c.parents:
        say("parent {parent}")
    say("message: {c.message}")
    say("files:")
    for name in sorted_keys(c.tree):
        say("  {name} {short(hex16(fnv(c.tree.get_or(name, ""))))}")
    return ok(nop())

fn cmd_checkout(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 2 and args.get(0) == "-b":
        let name = args.get(1)
        try create_branch(var repo, name)
        try check_switch(repo, head_tree(repo))
        repo.head_branch = name
        repo.detached = ""
        say("Switched to a new branch '{name}'")
        return ok(nop())

    if args.length() != 1:
        return fail("usage: checkout REF | checkout -b NAME")

    let target = args.get(0)
    if repo.merging:
        return fail("merge in progress")

    if repo.branches.contains(target):
        if repo.head_branch == target:
            say("Already on '{target}'")
            return ok(nop())

        let target_tree = tree_of(repo, repo.branches.get_or(target, ""))
        try check_switch(repo, target_tree)

        let old_head = head_tree(repo)
        apply_state(var repo, target_tree, target_tree.clone(), old_head)
        repo.head_branch = target
        repo.detached = ""
        say("Switched to branch '{target}'")
        return ok(nop())

    let id = try resolve(repo, target)
    let target_tree = tree_of(repo, id)
    try check_switch(repo, target_tree)

    let old_head = head_tree(repo)
    apply_state(var repo, target_tree, target_tree.clone(), old_head)
    repo.head_branch = ""
    repo.detached = id
    say("HEAD is now at {short(id)} {message_of(repo, id)}")
    return ok(nop())

fn cmd_reset(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 0 or args.length() > 2 or args.get(0) != "--hard":
        return fail("usage: reset --hard [REF]")

    var id = head_commit(repo)
    if args.length() == 2:
        id = try resolve(repo, args.get(1))
    if id == "":
        return fail("no commits yet")

    reset_hard(var repo, id)
    say("HEAD is now at {short(id)} {message_of(repo, id)}")
    return ok(nop())

fn cmd_merge(var repo: Repo, args: List[String]) Result[Unit, Fail]:
    if args.length() == 1 and args.get(0) == "--abort":
        if not repo.merging:
            return fail("no merge in progress")

        reset_hard(var repo, head_commit(repo))
        say("Merge aborted.")
        return ok(nop())

    if args.length() != 1:
        return fail("usage: merge BRANCH")
    if repo.merging:
        return fail("merge in progress")

    let head = head_commit(repo)
    if head == "":
        return fail("no commits yet")

    let name = args.get(0)
    if not repo.branches.contains(name) or repo.branches.get_or(name, "") == "":
        return fail("unknown branch '{name}'")

    let other = repo.branches.get_or(name, "")
    if is_dirty(repo):
        return fail("local changes would be overwritten")

    if is_ancestor(repo, other, head):
        say("Already up to date.")
        return ok(nop())

    let other_tree = tree_of(repo, other)
    let old_head = head_tree(repo)

    if is_ancestor(repo, head, other):
        try untracked_check(repo, sorted_keys(other_tree))
        apply_state(var repo, other_tree, other_tree.clone(), old_head)
        move_head(var repo, other)
        say("Fast-forward")
        return ok(nop())

    let base_tree = tree_of(repo, merge_base(repo, head, other))
    let plan = plan_merge(base_tree, old_head, other_tree, name)
    var names: List[String] = plan.work.keys()
    for key in plan.index.keys():
        names.append(key)
    try untracked_check(repo, names)
    apply_state(var repo, plan.work, plan.index, old_head)

    if plan.kinds.length() == 0:
        let id = make_commit(
            var repo, plan.index.clone(), [head, other], "Merge branch '{name}'"
        )
        move_head(var repo, id)
        say("Merge made by the 'three-way' strategy.")
        say("[{label(repo)} {short(id)}] Merge branch '{name}'")
        return ok(nop())

    repo.merging = true
    repo.merge_other = other
    repo.merge_branch = name
    repo.conflicts.clear()
    for path in plan.kinds.keys():
        repo.conflicts.add(path)

    for path in sorted_keys(plan.kinds):
        let kind = plan.kinds.get_or(path, "")

        if kind == "modify/delete":
            say("CONFLICT (modify/delete): {path}")
        else:
            say("CONFLICT ({kind}): Merge conflict in {path}")

    say("Automatic merge failed; fix conflicts and then commit the result.")
    return ok(nop())

fn run_command(var repo: Repo, words: List[String], raw: String, block: List[String]) Result[
    Unit, Fail
]:
    let command = words.get(0)
    let args = words.slice(1, words.length()).get()
    if command == "write" or command == "append":
        return cmd_write(var repo, args, block, command == "append")
    if command == "rm":
        return cmd_rm(var repo, args)
    if command == "mv":
        return cmd_mv(var repo, args)
    if command == "cat":
        return cmd_cat(repo, args)
    if command == "ls":
        return cmd_ls(repo)
    if command == "add":
        return cmd_add(var repo, args)
    if command == "status":
        return cmd_status(repo)
    if command == "commit":
        return cmd_commit(var repo, text_after_word(raw))
    if command == "log":
        return cmd_log(repo, args)
    if command == "diff":
        return cmd_diff(repo, args)
    if command == "branch":
        return cmd_branch(var repo, args)
    if command == "tag":
        return cmd_tag(var repo, args)
    if command == "show":
        return cmd_show(repo, args)
    if command == "checkout":
        return cmd_checkout(var repo, args)
    if command == "reset":
        return cmd_reset(var repo, args)
    if command == "merge":
        return cmd_merge(var repo, args)

    return fail("unknown command '{command}'")

fn read_all_lines() List[String]:
    var lines: List[String] = []
    var more = true

    while more:
        let next = read_line(stdin()).get()

        if let line = next:
            lines.append(line)
        else:
            more = false

    return lines

export fn main() Int:
    let lines = read_all_lines()
    var repo = new_repo()
    var pos = 0

    while pos < lines.length():
        let raw = lines.get(pos)
        pos += 1

        let text = raw.trim()

        if text != "" and not text.starts_with("#"):
            let words = split_words(raw)
            say("> {raw.trim_end()}")

            var block: List[String] = []

            if (
                words.length() == 2
                and (
                    words.get(0) == "write"
                    or words.get(0) == "append"
                )
            ):
                while pos < lines.length() and lines.get(pos) != ".":
                    block.append(lines.get(pos))
                    pos += 1

                pos += 1

            run_command(var repo, words, raw, block).or_else(report)

    stdout().flush().get()
    return 0
