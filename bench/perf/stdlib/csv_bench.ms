import (
	parse, stringify from "@std/data/csv.ms",
	keep, measure from "@std/test/bench.ms",
)

bench "csv.stringify":
	var rows: List[List[String]] = []
	for i in 0..5000:
		rows.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

	fn work() Result[Void, Error]:
		if s := stringify(rows): return keep(s.length())
		return keep(0)

	measure(5000, work)?

bench "csv.parse":
	var rows: List[List[String]] = []
	for i in 0..5000:
		rows.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

	csv_text := stringify(rows).get("")

	fn work() Result[Void, Error]:
		if r := parse(csv_text): return keep(r.length())
		return keep(0)

	measure(5000, work)?

bench "csv.parse escaped quote field":
	value := "a\"".repeat(8000)?
	text := f"\"{value.replace("\"", "\"\"")}\"\n"

	fn work() Void!:
		rows := parse(text)?
		return keep(rows[0][0].length())

	measure(1, work)?
