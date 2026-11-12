import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Rec:
	name: String
	score: Int

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	var recs = List[Rec]()

	for line in data.split("\n"):
		if line.is_empty(): continue

		f := line.split(" ")
		recs.append(Rec(f[0].clone(), f[1].parse_int().get(0)))

	sorted := recs.sorted(
		fn a,
		b: if a.score != b.score: b.score - a.score else: a.name.compare(b.name)
	)
	var check = 0
	for i in 0..sorted.length():
		check = (check * 31 + sorted[i].score + i) % 1000000007
	print("records: {sorted.length()}")
	print("checksum: {check}")
	for i in [0, 1, 2, sorted.length() - 1]:
		print("{sorted[i].name} {sorted[i].score}")
