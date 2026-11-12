import (
	parse from "@std/data/csv.ms",
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Total:
	rows: Int
	cents: Int

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	rows := parse(data).get()
	var regions = Map[String, Total]()
	var products = Map[String, Int]()
	var quoted = 0

	for i in 1..rows.length():
		r := rows[i]
		cents := r[3].parse_int().get(0) * r[4].parse_int().get(0)
		old := regions.get_or(r[1], Total(0, 0))
		regions[r[1].clone()] = Total(old.rows + 1, old.cents + cents)
		products[r[2].clone()] = products.get_or(r[2], 0) + cents
		if r[5].contains(","): quoted += 1

	print("rows: {rows.length() - 1}")
	print("quoted: {quoted}")
	for e in regions.entries().sorted(fn a, b: a.key.compare(b.key)):
		print("{e.key} {e.value.rows} {e.value.cents}")
	for e in products.entries().sorted(
		fn a,
		b: if a.value != b.value: b.value - a.value else: a.key.compare(b.key)
	).slice(0, 5).get():
		print("{e.key} {e.value}")
