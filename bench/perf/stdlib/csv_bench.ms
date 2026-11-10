import (
	keep, measure from "@std/test/bench.ms",
	parse, stringify from "@std/data/csv.ms",
)

bench "csv.stringify":
	var rows: List[List[String]] = []
	for i in 0..5000:
		rows.append(["{i}", "name {i}", "a,b", "quote\"d"])

	fn work() Result[Unit, Error]:
		if s := stringify(rows): return keep(s.length())

		return keep(0)

	try measure(5000, work)

bench "csv.parse":
	var rows: List[List[String]] = []
	for i in 0..5000:
		rows.append(["{i}", "name {i}", "a,b", "quote\"d"])

	csv_text := stringify(rows).get("")

	fn work() Result[Unit, Error]:
		if r := parse(csv_text): return keep(r.length())

		return keep(0)

	try measure(5000, work)

bench "csv.parse escaped quote field":
	value := try "a\"".repeat(8000)
	text := "\"{value.replace("\"", "\"\"")}\"\n"

	fn work() Unit!:
		rows := try parse(text)
		return keep(rows[0][0].byte_length())

	try measure(1, work)
