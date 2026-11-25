import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Rec {
	name String
	score Int
}

fn main() Void {
	data := read_all(stdin(), null).get().decode_utf8() or ""
	var recs = List[Rec]()

	for line in data.split("\n") {
		if line.is_empty() { continue }

		f := line.split(" ")
		recs.append(Rec(f[0].clone(), f[1].parse_int() or 0))
	}

	sorted := recs.sorted(
		(
			a,
			b,
		) => if a.score != b.score { b.score - a.score } else { a.name.compare(b.name) }
	)
	var check = 0
	for i in 0..sorted.length() {
		check = (check * 31 + sorted[i].score + i) % 1000000007
	}
	print(f"records: {sorted.length()}")
	print(f"checksum: {check}")
	for i in [0, 1, 2, sorted.length() - 1] {
		print(f"{sorted[i].name} {sorted[i].score}")
	}
}
