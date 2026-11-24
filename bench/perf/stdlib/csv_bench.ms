import parse, stringify from "@std/data/csv.ms"

type BenchData:
	rows List[List[String]]
	rows_2 List[List[String]]
	csv_text String
	value String
	text String

fn make_fixture() BenchData:
	var rows List[List[String]] = []
	for i in 0..5000:
		rows.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

	var rows_2 List[List[String]] = []
	for i in 0..5000:
		rows_2.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

	csv_text := stringify(rows_2).get_or("")
	value := "a\"".repeat(8000)
	text := f"\"{value.replace("\"", "\"\"")}\"\n"
	return BenchData(
		rows: rows,
		rows_2: rows_2,
		csv_text: csv_text.clone(),
		value: value,
		text: text,
	)

bench "csv.stringify" per 5000:
	stringify(fixture.rows).get_or("").length()

bench "csv.parse" per 5000:
	parse(fixture.csv_text).get_or([]).length()

bench "csv.parse escaped quote field":
	rows := parse(fixture.text)?
	rows[0][0].length()
