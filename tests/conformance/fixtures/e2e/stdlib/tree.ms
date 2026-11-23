// conform: tags=testing,tier-io
// conform: phase=test
import (
	panic from "@std/core.ms",
	canonicalize, create_directory, create_symlink, temporary, write_file from "@std/os/fs.ms",
	FileTree,
	MemoryTree,
	WalkEntry,
	host_tree,
	memory_tree,
	walk from "@std/os/tree.ms",
	expect_ok from "@std/test/test.ms",
)

fn paths(found: List[WalkEntry]) List[String]:
	return found.map(fn e: if e.directory: f"{e.path}/" else: e.path.clone())

fn total_size(tree: FileTree, names: List[String]) Int!:
	var total = 0
	for name in names:
		total += (tree.read(name, none)?).length()
	return ok(total)

fn sample() MemoryTree:
	var tree = memory_tree()
	tree.write_file("docs/guide.md", "guide".to_bytes()).get()
	tree.write_file("docs/api/index.md", "api".to_bytes()).get()
	tree.write_file("main.ms", "main".to_bytes()).get()
	tree.create_directory("empty").get()
	return tree

test "memory tree lists and reads":
	tree := sample()
	top := tree.children("", none) | expect_ok?
	if top.map(fn e: e.name.clone()) != ["docs", "empty", "main.ms"]: return panic(
		"top"
	)
	if not top[0].directory: return panic("docs is a directory")
	if top[2].directory: return panic("main.ms is a file")
	if ((tree.read("docs/./api/../guide.md", none) | expect_ok?) != "guide".to_bytes()): return panic(
		"clean path"
	)
	if (total_size(tree, ["main.ms", "docs/guide.md"]) | expect_ok?) != 9: return panic(
		"generic over FileTree"
	)

test "memory tree reports precise errors":
	var tree = sample()
	if (
		tree.read("nope", none).err() != Error(
			"filesystem: file or directory not found",
			kind: "ENOENT",
		)
	): return panic("missing")
	if (
		tree.read("docs", none).err() != Error(
			"filesystem: invalid input",
			kind: "EINVAL",
		)
	): return panic("read directory")
	if (
		tree.children("main.ms", none).err() != Error(
			"filesystem: invalid input",
			kind: "EINVAL",
		)
	): return panic("list file")
	if (
		tree.read("../x", none).err() != Error(
			"filesystem: invalid input",
			kind: "EINVAL",
		)
	): return panic("escape")
	if (
		tree.read("main.ms", 2).err() != Error(
			"filesystem: limit exceeded",
			kind: "EOVERFLOW",
		)
	): return panic("limit")
	if (
		tree.write_file("main.ms/inner", "x".to_bytes()).err() != Error(
			"filesystem: invalid input",
			kind: "EINVAL",
		)
	): return panic("parent is file")
	if (
		tree.remove("docs").err() != Error(
			"filesystem: directory not empty",
			kind: "ENOTEMPTY",
		)
	): return panic("not empty")

	tree.remove("docs", recursive: true)?
	if tree.exists("docs/api/index.md"): return panic("recursive remove")

	tree.remove("empty")?
	if paths(walk(tree) | expect_ok?) != ["main.ms"]: return panic("after removals")

test "walk is depth first and sorted":
	tree := sample()
	found := walk(tree) | expect_ok?
	if (
		paths(found) != [
			"docs/", "docs/api/", "docs/api/index.md", "docs/guide.md", "empty/",
			"main.ms"
		]
	): return panic("order")

	docs := walk(tree, "docs") | expect_ok?
	if paths(docs) != ["api/", "api/index.md", "guide.md"]: return panic("sub root")
	if (
		walk(tree, max_entries: 2).err() != Error(
			"filesystem: limit exceeded",
			kind: "EOVERFLOW",
		)
	): return panic("limit")

test "host tree walks the same way":
	dir := temporary("manuscript-tree-") | expect_ok?
	create_directory(f"{dir.path()}/b", true) | expect_ok?
	write_file(path: f"{dir.path()}/b/two.txt", data: "22").wait() | expect_ok?
	write_file(path: f"{dir.path()}/one.txt", data: "1").wait() | expect_ok?

	tree := host_tree(dir.path())
	if paths(walk(tree) | expect_ok?) != ["b/", "b/two.txt", "one.txt"]: return panic(
		"host walk"
	)
	if (tree.read("b/two.txt", none) | expect_ok?) != "22".to_bytes(): return panic(
		"host read"
	)
	if (
		tree.read("../etc", none).err() != Error(
			"filesystem: invalid input",
			kind: "EINVAL",
		)
	): return panic("host escape")

test "host tree follows links inside the root and refuses links that leave it":
	base := temporary("manuscript-tree-links-") | expect_ok?
	create_directory(f"{base.path()}/root/in", true) | expect_ok?
	create_directory(f"{base.path()}/outside", true) | expect_ok?
	write_file(path: f"{base.path()}/root/in/a.txt", data: "a").wait() | expect_ok?
	write_file(path: f"{base.path()}/outside/s.txt", data: "s").wait() | expect_ok?
	create_symlink(f"{base.path()}/root/inner", f"{base.path()}/root/in") | expect_ok?
	create_symlink(f"{base.path()}/root/out", f"{base.path()}/outside") | expect_ok?

	tree := host_tree(f"{base.path()}/root")
	if (tree.read("inner/a.txt", none) | expect_ok?) != "a".to_bytes(): return panic(
		"inner link"
	)
	invalid := Error("filesystem: invalid input", kind: "EINVAL")
	if tree.read("out/s.txt", none).err() != invalid: return panic("outer file")
	probe := tree.children("out", none)
	if probe.err() != invalid: return panic(f"outer directory: {probe.err()} real={canonicalize(f"{base.path()}/root/out")} root={canonicalize(f"{base.path()}/root")}")
	if tree.read("missing", none).err() == invalid: return panic("missing is not escape")

test "memory tree listing follows writes and removals":
	var tree = memory_tree()
	tree.write_file("a/b/one.txt", "1".to_bytes())?
	tree.write_file("a/two.txt", "2".to_bytes())?
	tree.remove("a/b", true)?

	names := (tree.children("a", none)?).map(fn e: e.name.clone())
	if names != ["two.txt"]: return panic(f"children {names}")
	if (tree.children("", none)?).length() != 1: return panic("root")

test "a file cannot be an ancestor of a directory or file":
	var tree = memory_tree()
	tree.write_file("a", "1".to_bytes())?

	deep := tree.write_file("a/b/c", "2".to_bytes())
	if deep.is_ok() or deep.err().kind != "EINVAL": return panic("write below a file")

	made := tree.create_directory("a/d")
	if made.is_ok() or made.err().kind != "EINVAL": return panic("directory below a file")

	if paths(walk(tree)?) != ["a"]: return panic(f"walk {paths(walk(tree)?)}")
	if (tree.read("a", none)?).length() != 1: return panic("file replaced")
