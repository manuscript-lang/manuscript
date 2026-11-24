// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	CsvOptions, each_cell, parse from "@std/data/csv.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

fn visited(text String, options CsvOptions = CsvOptions()) List[List[String]]:
	var rows = List[List[String]]()

	add := fn(row Int, col Int, cell String) Void:
		if col == 0: rows.append([])
		rows[row].append(cell.clone())

	each_cell(text, add, options).get()
	return rows

test "each_cell visits the cells parse returns":
	texts := [
		"a,b,c\n1,2,3\n", "a,b\r\n1,2", "x,\"y,z\",w\n\"q\"\"r\",,end\n", "\n\na,b\n\n",
		"é,ü\n日本,語", "\"line\r\nbreak\",2\n", ",\n"
	]
	for t in texts:
		expect_equal(visited(t), parse(t).get())?

test "each_cell reports malformed input and its limits":
	expect_true(each_cell("a,\"b\n", (r, c, cell) => void).is_error())?

	options := CsvOptions(max_rows: 1)
	expect_true(each_cell("a\nb\n", (r, c, cell) => void, options).is_error())?
