// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	change_directory, working_directory from "@std/os/env.ms",
	GlobOptions,
	PathEntry,
	create_directory,
	glob,
	temporary,
	write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type RestoreDirectory:
	path String

fn move RestoreDirectory.close() Void!:
	return change_directory(self.path)

fn matched_paths(root String, options GlobOptions) List[String]!:
	entries := glob(root, options)?
	return ok(entries.map(fn(entry PathEntry) String => entry.path.clone()))

test "glob keeps dot named and parent query results relative to their root":
	directory := temporary("manuscript-glob-relative-")?
	_restore := RestoreDirectory(working_directory()?)
	create_directory(f"{directory.path()}/src/deep", recursive: true)?
	for name in ["a.txt", "café.txt", "src/b.txt", "src/deep/c.txt"]:
		write_file(f"{directory.path()}/{name}", "file").wait()?
	change_directory(directory.path())?

	all := GlobOptions(patterns: ["**/*.txt"])
	expected := ["a.txt", "café.txt", "src/b.txt", "src/deep/c.txt"]
	for root in [".", "./", "src/..", directory.path()]:
		expect_equal(matched_paths(root, all)?, expected)?
	expect_equal(
		matched_paths(".", GlobOptions(patterns: ["*.txt"]))?,
		["a.txt", "café.txt"],
	)?
	expect_equal(matched_paths("src", all)?, ["b.txt", "deep/c.txt"])?
	expect_equal(
		matched_paths("src", GlobOptions(patterns: ["../*.txt"]))?,
		["../a.txt", "../café.txt"],
	)?
	expect_equal(
		matched_paths(
			".",
			GlobOptions(patterns: ["**/*.txt"], exclude: ["src/**"]),
		)?,
		["a.txt", "café.txt"],
	)?

	selected := glob(".", all, fn(entry PathEntry) Bool => entry.path == "src")?
	expect_equal(
		selected.map(fn(entry PathEntry) String => entry.path.clone()),
		["a.txt", "café.txt"],
	)?

test "glob patterns ignore dot segments and never match the root":
	directory := temporary("manuscript-glob-dots-")?
	root := directory.path()
	create_directory(f"{root}/a", recursive: true)?
	for name in ["x.ms", ".dot.ms", "a/z.ms"]:
		write_file(f"{root}/{name}", "file").wait()?

	expect_equal(matched_paths(root, GlobOptions(patterns: [".*"]))?, [".dot.ms"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["**/.*"]))?, [".dot.ms"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["./*.ms"]))?, ["x.ms"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["a/./z.ms"]))?, ["a/z.ms"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["a//z.ms"]))?, ["a/z.ms"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["*/"]))?, ["a"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["**/"]))?, ["a"])?
	expect_equal(matched_paths(root, GlobOptions(patterns: ["x.ms/"]))?, [])?
	expect_equal(
		matched_paths(root, GlobOptions(patterns: ["**/*"], exclude: ["a/"]))?,
		["x.ms"],
	)?
