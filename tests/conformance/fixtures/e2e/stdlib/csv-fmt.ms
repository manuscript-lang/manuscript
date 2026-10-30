# conform: tags=control-flow,formatter,interpolation,lists,modules,parser,stdlib-csv,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/csv.ms
import expect_equal, expect_false from "@std/test.ms"
import parse, stringify, CsvOptions, CsvError from "@std/csv.ms"

test "CSV retains single empty fields and distinguishes empty rows":
    for ending in ["\n", "\r\n"]:
        for delimiter in [",", ";", "\t"]:
            let options = CsvOptions(delimiter, ending)
            let rows = [["a"], [""], ["b"], [""], [""]]
            let expected = "a{ending}\"\"{ending}b{ending}\"\"{ending}\"\"{ending}"
            let text = try stringify(rows, options)
            try expect_equal(text, expected)
            try expect_equal((try parse(text, options)), rows)

            let empty_rows: List[List[String]] = [[], []]
            try expect_equal((try stringify(empty_rows, options)), "{ending}{ending}")

            let no_rows: List[List[String]] = []
            try expect_equal((try parse("{ending}{ending}", options)), no_rows)
            try expect_false(
                (
                    (
                        try parse(
                            "{ending}\"\"{ending}{ending}\"\"", options
                        )
                    ) != [[""], [""]]
                )
            )
            try expect_equal(
                (try stringify([["", ""]], options)), "{delimiter}{ending}"
            )

test "CSV quoted empty fields respect exact row cell and byte budgets":
    for ending in ["\n", "\r\n"]:
        let options = CsvOptions(",", ending)
        let rows = [[""], ["a"], [""]]
        let text = "\"\"{ending}a{ending}\"\"{ending}"
        let bytes = text.byte_length()
        try expect_equal((try stringify(rows, options, bytes)), text)

        let limited_text: Result[String, CsvError] = error(CsvError.LimitExceeded)
        try expect_equal(stringify(rows, options, bytes - 1), limited_text)
        try expect_equal(stringify([[""]], options, 0), limited_text)
        try expect_equal((try parse(text, options, 3, 3)), rows)

        let limited_rows: Result[List[List[String]], CsvError] = error(
            CsvError.LimitExceeded
        )
        try expect_equal(parse(text, options, 2), limited_rows)
        try expect_equal(parse(text, options, max_cells: 2), limited_rows)
        try expect_equal(parse("\"\"", options, 0), limited_rows)
        try expect_equal(parse("\"\"", options, max_cells: 0), limited_rows)

test "CSV preserves whitespace and normalizes quoted CRLF":
    let options = CsvOptions(",", "\n")
    let rows = [[" "], ["\t"], ["line\n\nbreak"], ["\""], ["", "", ""]]
    try expect_equal((try parse(try stringify(rows, options), options)), rows)
    try expect_false(
        try parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options) != [
            ["line\n\nbreak"], [""]
        ]
    )

test "CSV quotes delimiters multiline cells and line endings":
    let options = CsvOptions(",", "\n")
    let rows = [["a,b", "say \"hi\"", "line\nbreak"], ["", "é", "last"]]
    let text = try stringify(rows, options)
    try expect_equal((try parse(text, options, 2, 6)), rows)

    let windows = CsvOptions(";", "\r\n")
    try expect_equal((try stringify([["a", "b"]], windows)), "a;b\r\n")

test "CSV rejects malformed records invalid options and limits":
    let options = CsvOptions(",", "\n")
    let malformed: Result[List[List[String]], CsvError] = error(CsvError.InvalidData)
    try expect_equal(parse("\"unterminated", options), malformed)
    for text in ["\"\"x\n", "x\"\"\n", "\"\"\"\n"]:
        try expect_equal(parse(text, options), malformed)

    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    try expect_equal(parse("a,b\n", options, max_cells: 1), limited)
    try expect_equal(parse("a\nb\n", options, 1), limited)

    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    try expect_equal(stringify([["a"]], CsvOptions("::", "\n")), invalid)
