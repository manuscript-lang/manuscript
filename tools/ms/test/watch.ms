// `--watch`: the files a run depends on, read from the sources, and the command lines of each run.
import (
	create_directory, remove, temporary_directory, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	build_arguments,
	local_imports,
	once_arguments,
	signature,
	watched_files from "../watch.ms",
)

test "local imports are the relative module paths, spelled from their directory":
	text := "import a from \"./a.ms\"\nimport (\n\tb from \"../up/b.ms\",\n\tc from \"@std/io/io.ms\",\n)\n"
	expect_equal(
		local_imports(text, "/p/src", Map[String, String]()),
		["/p/src/a.ms", "/p/up/b.ms"],
	)?

test "a path in a text literal is not an import":
	expect_equal(local_imports("x := \"./a.ms\"\n", "/p", Map[String, String]()), [])?

test "the run command line drops --watch":
	expect_equal(
		once_arguments(["ms", "check", "--watch", "main.ms"]),
		["ms", "check", "main.ms"],
	)?

test "run builds into the executable and keeps no program arguments":
	words := build_arguments(
		["ms", "run", "main.ms", "--watch", "--", "one"],
		"/t/program-1",
	)
	expect_equal(words, ["ms", "build", "main.ms", "-o", "/t/program-1"])?

test "a path's signature changes with its content and is missing when absent":
	directory := temporary_directory("watch-test-")?
	path := join([directory.clone(), "f.txt"])
	expect_equal(signature(path), "missing")?
	write_file(path, "a").wait()?

	first := signature(path)
	write_file(path, "bb", true).wait()?
	expect_equal(first != signature(path), true)?
	void remove(path)

test "the watched files follow imports, including one not created yet":
	directory := temporary_directory("watch-test-")?
	main := join([directory.clone(), "main.ms"])
	dep := join([directory.clone(), "dep.ms"])
	late := join([directory.clone(), "late.ms"])
	write_file(main, "import a from \"./dep.ms\"\n").wait()?
	write_file(dep, "import b from \"./late.ms\"\n").wait()?

	files := watched_files(main)
	expect_equal(files.contains(dep), true)?
	expect_equal(files.contains(late), true)?

test "an alias import names its target, and a file alias takes no more segments":
	var aliases = Map[String, String]()
	aliases.add("@lib", "/p/lib")
	aliases.add("@one", "/p/one.ms")

	text := "import (\n\ta from \"@lib/a.ms\",\n\tb from \"@one\",\n\tc from \"@other/c.ms\",\n)\n"
	expect_equal(local_imports(text, "/p", aliases), ["/p/lib/a.ms", "/p/one.ms"])?

test "the watched files include embedded trees and member projects":
	directory := temporary_directory("watch-test-")?
	assets := join([directory.clone(), "assets"])
	create_directory(join([assets.clone(), "deep"]), true)?
	write_file(join([assets.clone(), "deep", "a.txt"]), "a").wait()?
	write_file(
		join([directory.clone(), "ms.toml"]),
		"[project]\nname = \"p\"\nsource = \".\"\nentry = \"main.ms\"\n\n[embed]\n\"@assets\" = \"./assets\"\n",
	).wait()?

	main := join([directory.clone(), "main.ms"])
	write_file(main, "export fn main() Int:\n\treturn 0\n").wait()?

	files := watched_files(main)
	expect_equal(files.contains(join([assets.clone(), "deep", "a.txt"])), true)?
	expect_equal(files.contains(join([directory.clone(), "ms.toml"])), true)?
