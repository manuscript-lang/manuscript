import (
	parse from "@std/data/json.ms",
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Rec:
	id: Int
	user: String
	score: Int
	active: Bool
	tags: List[String]
	name: String

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	recs := parse[List[Rec]](data).get()
	var scores = Map[String, Int]()
	var tags = Map[String, Int]()
	var active = 0
	var name_bytes = 0

	for r in recs:
		scores.update(r.user.clone(), 0, fn v: v + r.score)
		for t in r.tags:
			tags.update(t.clone(), 0, fn v: v + 1)
		if r.active:
			active += 1
		name_bytes += r.name.length()

	print("records: {recs.length()}")
	print("active: {active}")
	print("name bytes: {name_bytes}")
	for e in scores.entries().sorted(
		fn a,
		b: if a.value != b.value: b.value - a.value else: a.key.compare(b.key)
	).slice(0, 5).get():
		print("{e.key} {e.value}")
	for e in tags.entries().sorted(fn a, b: a.key.compare(b.key)):
		print("{e.key} {e.value}")
