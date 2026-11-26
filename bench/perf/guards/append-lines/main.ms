// Guard: a loop that builds its output with `out += f"..."` after a `continue` and a
// split stays linear. The string was copied whole on every append, so 80000 lines took
// 4.7 s (issue #6837), and the count grew with the square of the line count.
fn main() Void {
	var data = ""
	for i in 0..30000 { data += f"name{i} {i % 997}\n" }

	var out = ""
	var total = 0

	for line in data.split("\n") {
		if line.is_empty() { continue }

		f := line.split(" ").collect()
		score := f[1].parse_int() or 0
		total += score
		out += f"{f[0].pad_end(12, " ")} {score.to_string().pad_start(8, " ")} {score * 3 / 7}\n"
	}

	print(f"{out.length()} {total}")
}
