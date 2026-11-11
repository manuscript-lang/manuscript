import (
	Align, Table from "@std/cli/table.ms",
	expect_equal from "@std/test/test.ms",
)

fn build(columns: List[Align], rows: List[List[String]]) Table!:
	var table = Table(columns: columns)
	for row in rows:
		table.add(row.clone())?
	return ok(table)

test "table aligns columns with no added trailing spaces or final LF":
	rows := [["name", "count"], ["tea", "2"], ["coffee", "30"]]
	table := build([Align.Left, Align.Right], rows)?
	expect_equal(table.render(), "name    count\ntea         2\ncoffee     30")?

	var tight = Table(columns: [Align.Left, Align.Left], padding: 1)
	for row in rows:
		tight.add(row.clone())?
	expect_equal(tight.render(), "name   count\ntea    2\ncoffee 30")?

	centered := build([Align.Center, Align.Center], [["abc", "abcd"], ["x", "y"]])?
	expect_equal(centered.render(), "abc  abcd\n x    y")?

test "table keeps combining wide and emoji sequences intact":
	rows := [["é", "a"], ["界", "b"], ["👩‍💻", "c"], ["·", "d"]]
	var table = Table(columns: [Align.Left, Align.Left], padding: 1)
	for row in rows:
		table.add(row.clone())?
	expect_equal(table.render(), "é  a\n界 b\n👩‍💻 c\n·  d")?

test "table indents lines and omits trailing empty cells":
	var table = Table(columns: [Align.Left, Align.Left], indent: 2)
	table.add(["a", "text"])?
	table.add(["long", ""])?
	table.add(["", ""])?
	expect_equal(table.render(), "  a     text\n  long\n")?

test "table renders empty tables and zero column rows":
	empty := Table(columns: [Align.Left])
	expect_equal(empty.render(), "")?

	var none = Table(columns: [])
	none.add([])?
	none.add([])?
	expect_equal(none.render(), "\n")?

test "table add rejects wrong cell counts and controls":
	malformed: Unit! := error(
		Error("table: row has 1 cells, expected 2", kind: "EBADMSG")
	)
	var table = Table(columns: [Align.Left, Align.Right])
	expect_equal(table.add(["a"]), malformed)?
	for cell in [
		"tab\there", "line\nbreak", "return\r", "\u{0}", "\u{1b}[31mred", "\u{85}",
		"\u{2028}", "\u{2029}"
	]:
		expect_equal(table.add([cell.clone(), "x"]).is_error(), true)?
	expect_equal(table.render(), "")?

test "table grows after rendering":
	var table = Table(columns: [Align.Left, Align.Right])
	table.add(["tea", "2"])?
	expect_equal(table.render(), "tea  2")?
	table.add(["coffee", "30"])?
	expect_equal(table.render(), "tea      2\ncoffee  30")?

test "display_width measures terminal columns":
	expect_equal("abc".display_width(), ok(3))?
	expect_equal("界".display_width(), ok(2))?
	expect_equal("e\u{301}".display_width(), ok(1))?
