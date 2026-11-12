// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	CsvOptions, parse, stringify from "@std/data/csv.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

test "CSV retains single empty fields and distinguishes empty rows":
	for ending in ["\n", "\r\n"]:
		for delimiter in [",", ";", "\t"]:
			options := CsvOptions(delimiter.clone(), ending.clone())
			rows := [["a"], [""], ["b"], [""], [""]]
			expected := "a{ending}\"\"{ending}b{ending}\"\"{ending}\"\"{ending}"
			text := stringify(rows, options)?
			expect_equal(text, expected)?
			expect_equal((parse(text, options)?), rows)?

			empty_rows: List[List[String]] := [[], []]
			expect_equal((stringify(empty_rows, options)?), "{ending}{ending}")?

			no_rows: List[List[String]] := []
			expect_equal((parse("{ending}{ending}", options)?), no_rows)?
			expect_false(
				(
					(
						parse(
							"{ending}\"\"{ending}{ending}\"\"",
							options,
						)?
					) != [[""], [""]]
				)
			)?
			expect_equal((stringify([["", ""]], options)?), "{delimiter}{ending}")?

test "CSV quoted empty fields respect exact row cell and byte budgets":
	for ending in ["\n", "\r\n"]:
		options := CsvOptions(",", ending.clone())
		rows := [[""], ["a"], [""]]
		text := "\"\"{ending}a{ending}\"\"{ending}"
		bytes := text.byte_length()
		expect_equal((stringify(rows, options, bytes)?), text)?

		limited_text: String! := error(Error("CSV: limit exceeded", kind: "EOVERFLOW"))
		expect_equal(stringify(rows, options, bytes - 1), limited_text)?
		expect_equal(stringify([[""]], options, 0), limited_text)?
		expect_equal((parse(text, CsvOptions(",", ending.clone(), 3, 3))?), rows)?

		limited_rows: List[List[String]]! := error(
			Error("CSV: limit exceeded", kind: "EOVERFLOW")
		)
		expect_equal(parse(text, CsvOptions(",", ending.clone(), 2)), limited_rows)?
		expect_equal(
			parse(text, CsvOptions(",", ending.clone(), max_cells: 2)),
			limited_rows,
		)?
		expect_equal(parse("\"\"", CsvOptions(",", ending.clone(), 0)), limited_rows)?
		expect_equal(
			parse("\"\"", CsvOptions(",", ending.clone(), max_cells: 0)),
			limited_rows,
		)?

test "CSV preserves whitespace and normalizes quoted CRLF":
	options := CsvOptions(",", "\n")
	rows := [[" "], ["\t"], ["line\n\nbreak"], ["\""], ["", "", ""]]
	expect_equal((parse(stringify(rows, options)?, options)?), rows)?
	expect_false(
		parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options)? != [
			["line\n\nbreak"],
			[""],
		]
	)?

test "CSV quotes delimiters multiline cells and line endings":
	options := CsvOptions(",", "\n")
	rows := [["a,b", "say \"hi\"", "line\nbreak"], ["", "é", "last"]]
	text := stringify(rows, options)?
	expect_equal((parse(text, CsvOptions(",", "\n", 2, 6))?), rows)?

	windows := CsvOptions(";", "\r\n")
	expect_equal((stringify([["a", "b"]], windows)?), "a;b\r\n")?

fn malformed(line: Int, column: Int, reason: String) List[List[String]]!:
	return error(
		Error(
			"CSV {line}:{column}: {reason}",
			kind: "EBADMSG",
			details: {
				"line": line.to_string(),
				"column": column.to_string(),
				"reason": reason.clone()
			},
		)
	)

test "CSV malformed records name their line and column":
	options := CsvOptions(",", "\n")
	expect_equal(
		parse("\"unterminated", options),
		malformed(1, 1, "unterminated quoted cell"),
	)?
	expect_equal(
		parse("a,b\nc,\"x\"y\n", options),
		malformed(
			2,
			6,
			"expected a delimiter or line end after the closing quote",
		),
	)?
	expect_equal(
		parse("a,b\nc,d\"e\n", options),
		malformed(2, 4, "quote inside an unquoted cell"),
	)?
	expect_equal(
		parse("é,\"ü\"x", options),
		malformed(
			1,
			6,
			"expected a delimiter or line end after the closing quote",
		),
	)?

test "CSV rejects malformed records invalid options and limits":
	options := CsvOptions(",", "\n")
	for text in ["\"\"x\n", "x\"\"\n", "\"\"\"\n"]:
		expect_true(parse(text, options).is_error())?

	limited: List[List[String]]! := error(
		Error("CSV: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(parse("a,b\n", CsvOptions(max_cells: 1)), limited)?
	expect_equal(parse("a\nb\n", CsvOptions(max_rows: 1)), limited)?

	invalid: String! := error(Error("CSV: invalid input", kind: "EINVAL"))
	expect_equal(stringify([["a"]], CsvOptions("::", "\n")), invalid)?

test "CSV quoted fields preserve zero one and many escaped quotes":
	for value in ["", "plain", "\"", "a\"b", "\"\"", "é\"日\"fin", "a\r\nb\"c\"d"]:
		encoded := "\"{value.replace("\"", "\"\"")}\""
		expected := [[value.replace("\r\n", "\n"), "tail"]]

		for delimiter in [",", ";", "\t"]:
			options := CsvOptions(delimiter.clone())
			for ending in ["", "\n", "\r\n"]:
				expect_equal(
					(
						parse(
							"{encoded}{delimiter}tail{ending}",
							options,
						)?
					),
					expected,
				)?

	value := "a\"日".repeat(8000)?
	encoded := "\"{value.replace("\"", "\"\"")}\"\n"
	expect_equal((parse(encoded)?), [[value]])?

test "CSV escaped fields preserve malformed closing quote locations":
	for text in ["\"a\"\"b", "\"a\"\"b\"\"c", "\"é\"\"日\"x"]:
		result := parse(text)
		expect_true(result.is_error())?
		expect_equal(result.err().kind, "EBADMSG")?

	expect_equal(parse("\"a\"\"b").err().message, "CSV 1:1: unterminated quoted cell")?
	expect_equal(
		parse("\"é\"\"日\"x").err().message,
		"CSV 1:7: expected a delimiter or line end after the closing quote",
	)?

test "CSV quote scanning preserves Unicode and exact backslash dot":
	for field in ["é日😀", "x\\.", "\\.x", "\\", ".", "a b", "x "]:
		expect_equal((stringify([[field.clone(), "tail"]])?), "{field},tail\n")?
	for field in ["\\.", " x", " x", "\tx", " x", "a,b", "a\"b"]:
		expect_equal(
			(stringify([[field.clone(), "tail"]])?),
			"\"{field.replace("\"", "\"\"")}\",tail\n",
		)?

	for delimiter in [";", "\t", "|", "\\", "."]:
		for ending in ["\n", "\r\n"]:
			options := CsvOptions(delimiter.clone(), ending.clone())
			field := "a{delimiter}日"
			text := "\"{field}\"{delimiter}tail{ending}"
			expect_equal(
				(
					stringify(
						[[field.clone(), "tail"]],
						options,
						text.byte_length(),
					)?
				),
				text,
			)?

			failure: String! := error(Error("CSV: limit exceeded", kind: "EOVERFLOW"))
			expect_equal(
				stringify(
					[[field.clone(), "tail"]],
					options,
					text.byte_length() - 1,
				),
				failure,
			)?

test "CSV stringify retains invalid option and negative budget errors":
	invalid: String! := error(Error("CSV: invalid input", kind: "EINVAL"))
	for delimiter in ["", "::", "é", "\"", "\r", "\n"]:
		expect_equal(stringify([["a"]], CsvOptions(delimiter.clone())), invalid)?
	for ending in ["", "\r", "x"]:
		expect_equal(
			stringify([["a"]], CsvOptions(line_ending: ending.clone())),
			invalid,
		)?
	expect_equal(stringify([["a"]], max_bytes: -1), invalid)?
	expect_equal(stringify([["a"]], CsvOptions("::", "x"), -1), invalid)?

	no_rows: List[List[String]] := []
	expect_equal((stringify(no_rows, max_bytes: 0)?), "")?
