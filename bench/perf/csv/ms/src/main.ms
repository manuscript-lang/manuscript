import (
	parse, stringify from "@std/data/csv.ms",
	stdout from "@std/io/io.ms",
	monotonic from "@std/time.ms",
)

// Parses 5000 rows 200 times, then writes them back 200 times, and prints each best
// run in microseconds.
// The "quoted" shape has quoted and escaped cells; "plain" has none.
fn rows_of(shape String) String:
	var text = ""

	for i in 0..5000:
		if shape == "quoted": text = text.concat(
			f"{i},name {i},\"a,b\",\"quote\"\"d\"\n"
		)
		else: text = text.concat(f"{i},name {i},alpha,beta,gamma\n")

	return text

fn main() Void:
	for shape in ["quoted", "plain"]:
		text := rows_of(shape)
		var best = 9223372036854775807
		var count = 0

		for _round in 0..200:
			started := monotonic()
			result := parse(text)
			elapsed := monotonic().difference(started).to_nanoseconds()
			count = result.get().length()
			if elapsed < best: best = elapsed

		_written := stdout().write(
			f"manuscript {shape} rows={count} best_us={best / 1000}\n"
		)
		rows := parse(text).get()
		var best_write = 9223372036854775807
		var written = 0

		for _round in 0..200:
			started := monotonic()
			encoded := stringify(rows)
			elapsed := monotonic().difference(started).to_nanoseconds()
			written = encoded.get().length()
			if elapsed < best_write: best_write = elapsed

		_wrote := stdout().write(
			f"manuscript {shape}-write bytes={written} best_us={best_write / 1000}\n"
		)
