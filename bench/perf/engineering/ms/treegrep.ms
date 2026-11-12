import (
	arguments from "@std/os/env.ms",
	list, read_file from "@std/os/fs.ms",
)

type Found:
	files: Int
	matches: Int

// Counts the lines containing a pattern in every file under a directory.
fn scan(dir: String) Found:
	var found = Found(0, 0)

	for entry in list(dir).get():
		path := "{dir}/{entry.name}"

		if entry.directory:
			inner := scan(path)
			found = Found(found.files + inner.files, found.matches + inner.matches)
			continue

		found = Found(found.files + 1, found.matches)

		text := read_file(path).wait().get().decode_utf8().get("")
		for line in text.split("\n"):
			if line.contains(" POST /api/v2/item/17") and line.contains(" 500 "):
				found = Found(found.files, found.matches + 1)

	return found

fn main() Unit:
	found := scan(arguments()[0])
	print("files: {found.files}")
	print("matches: {found.matches}")
