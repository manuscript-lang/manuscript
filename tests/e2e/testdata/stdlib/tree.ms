import (
    FileTree,
    MemoryTree,
    memory_tree,
    host_tree,
    walk,
    WalkEntry
) from "@std/os/tree.ms"
import FileSystemError, create_directory, write_file, temporary from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import expect_ok from "@std/test/test.ms"

fn paths(found: List[WalkEntry]) List[String]:
    return found.map(fn e: if e.directory: "{e.path}/" else: e.path.clone())

fn total_size(tree: FileTree, names: List[String]) Int!FileSystemError:
    var total = 0
    for name in names:
        total += (try tree.read(name, none)).length()
    return ok(total)

fn sample() MemoryTree:
    var tree = memory_tree()
    tree.write_file("docs/guide.md", "guide".to_bytes()).get()
    tree.write_file("docs/api/index.md", "api".to_bytes()).get()
    tree.write_file("main.ms", "main".to_bytes()).get()
    tree.create_directory("empty").get()
    return tree

test "memory tree lists and reads":
    let tree = sample()
    let top = tree.children("", none) | try expect_ok
    if top.map(fn e: e.name.clone()) != ["docs", "empty", "main.ms"]: return panic(
        "top"
    )
    if not top[0].directory: return panic("docs is a directory")
    if top[2].directory: return panic("main.ms is a file")
    if (
        (
            tree.read("docs/./api/../guide.md", none) | try expect_ok
        ) != "guide".to_bytes()
    ): return panic("clean path")
    if (total_size(tree, ["main.ms", "docs/guide.md"]) | try expect_ok) != 9: return panic(
        "generic over FileTree"
    )

test "memory tree reports precise errors":
    var tree = sample()
    if tree.read("nope", none).err() != FileSystemError.NotFound: return panic(
        "missing"
    )
    if tree.read("docs", none).err() != FileSystemError.InvalidInput: return panic(
        "read directory"
    )
    if tree.children("main.ms", none).err() != FileSystemError.InvalidInput: return panic(
        "list file"
    )
    if tree.read("../x", none).err() != FileSystemError.InvalidInput: return panic(
        "escape"
    )
    if tree.read("main.ms", 2).err() != FileSystemError.LimitExceeded: return panic(
        "limit"
    )
    if (
        tree.write_file(
            "main.ms/inner", "x".to_bytes()
        ).err() != FileSystemError.InvalidInput
    ): return panic("parent is file")
    if tree.remove("docs").err() != FileSystemError.NotEmpty: return panic("not empty")

    try tree.remove("docs", recursive: true)
    if tree.exists("docs/api/index.md"): return panic("recursive remove")

    try tree.remove("empty")
    if paths(walk(tree) | try expect_ok) != ["main.ms"]: return panic("after removals")

test "walk is depth first and sorted":
    let tree = sample()
    let found = walk(tree) | try expect_ok
    if (
        paths(found) != [
            "docs/", "docs/api/", "docs/api/index.md", "docs/guide.md", "empty/",
            "main.ms"
        ]
    ): return panic("order")

    let docs = walk(tree, "docs") | try expect_ok
    if paths(docs) != ["api/", "api/index.md", "guide.md"]: return panic("sub root")
    if walk(tree, max_entries: 2).err() != FileSystemError.LimitExceeded: return panic(
        "limit"
    )

test "host tree walks the same way":
    let dir = temporary("manuscript-tree-") | try expect_ok
    create_directory("{dir.path()}/b", true) | try expect_ok
    write_file(path: "{dir.path()}/b/two.txt", data: "22") | try expect_ok
    write_file(path: "{dir.path()}/one.txt", data: "1") | try expect_ok

    let tree = host_tree(dir.path())
    if paths(walk(tree) | try expect_ok) != ["b/", "b/two.txt", "one.txt"]: return panic(
        "host walk"
    )
    if (tree.read("b/two.txt", none) | try expect_ok) != "22".to_bytes(): return panic(
        "host read"
    )
    if tree.read("../etc", none).err() != FileSystemError.InvalidInput: return panic(
        "host escape"
    )
