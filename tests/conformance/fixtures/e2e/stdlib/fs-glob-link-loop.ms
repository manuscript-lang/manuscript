// conform: tags=testing,tier-io
// conform: phase=test
import (
	GlobOptions,
	PathEntry,
	create_symlink,
	glob,
	temporary,
	write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

fn matched_paths(root: String, options: GlobOptions) List[String]!:
	entries := glob(root, options)?
	return ok(entries.map(fn(entry: PathEntry) String: entry.path.clone()))

test "glob following links skips dangling and looping links like any link without a directory":
	directory := temporary("manuscript-glob-loop-")?
	root := directory.path()
	write_file("{root}/a.txt", "file").wait()?
	create_symlink("{root}/dangling", "{root}/nowhere")?
	create_symlink("{root}/loop", "{root}/loop")?

	for follow in [false, true]:
		options := GlobOptions(patterns: ["*"], follow_links: follow)
		expect_equal(matched_paths(root, options)?, ["a.txt", "dangling", "loop"])?
