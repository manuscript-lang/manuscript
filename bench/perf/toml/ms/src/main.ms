import (
	parse from "@std/data/toml.ms",
	stdout from "@std/io/io.ms",
	StringBuilder from "@std/string.ms",
	monotonic from "@std/time.ms",
)

fn document(count: Int) String:
	var sb = StringBuilder()
	for i in 0..count:
		sb.append("[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
	return sb.build()

fn parse_ok(text: String) Int:
	if parse(text).is_ok(): return 1
	return 0

// Parses the document 200 times and prints the best run in microseconds.
fn main() Unit:
	text := document(2000)
	var best = 1000000000000
	var ok = 0

	for run in 0..200:
		started := monotonic()
		ok = parse_ok(text) + run * 0

		elapsed := monotonic().difference(started).to_nanoseconds()
		if elapsed < best: best = elapsed

	_ignored := stdout().write(
		"ms toml bytes={text.byte_length()} ok={ok} best_us={best / 1000}\n"
	)
