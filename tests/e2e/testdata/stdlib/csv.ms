import {expect_equal, expect_false, expect_ok} from "@std/testing.ms"
import {parse, stringify, CsvOptions, CsvError} from "@std/csv.ms"

test "CSV retains single empty fields and distinguishes empty rows":
    for ending in ["\n", "\r\n"]:
        for delimiter in [",", ";", "\t"]:
            let options = CsvOptions(delimiter: delimiter, line_ending: ending)
            let rows = [["a"], [""], ["b"], [""], [""]]
            let expected = "a{ending}\"\"{ending}b{ending}\"\"{ending}\"\"{ending}"
            let text = (stringify(rows: rows, options: options) | try expect_ok)
            text | try expect_equal(expected: expected)
            parse(text: text, options: options) | try expect_ok | try expect_equal(
                expected: rows
            )
            let empty_rows: List[List[String]] = [[], []]
            (
                (
                    (
                        stringify(
                            rows: empty_rows,
                            options: options
                        ) | try expect_ok
                    ) != "{ending}{ending}"
                )
            ) | try expect_false
            let no_rows: List[List[String]] = []
            parse(text: "{ending}{ending}", options: options) | try expect_ok | try expect_equal(
                expected: no_rows
            )
            (
                (
                    (
                        parse(
                            text: "{ending}\"\"{ending}{ending}\"\"",
                            options: options
                        ) | try expect_ok
                    ) != [[""], [""]]
                )
            ) | try expect_false
            (
                (
                    (
                        stringify(
                            rows: [["", ""]],
                            options: options
                        ) | try expect_ok
                    ) != "{delimiter}{ending}"
                )
            ) | try expect_false

test "CSV quoted empty fields respect exact row cell and byte budgets":
    for ending in ["\n", "\r\n"]:
        let options = CsvOptions(delimiter: ",", line_ending: ending)
        let rows = [[""], ["a"], [""]]
        let text = "\"\"{ending}a{ending}\"\"{ending}"
        let bytes = text.byte_length()
        stringify(rows: rows, options: options, max_bytes: bytes) | try expect_ok | try expect_equal(
            expected: text
        )
        let limited_text: Result[String, CsvError] = error(CsvError.LimitExceeded)
        (
            (
                stringify(
                    rows: rows,
                    options: options,
                    max_bytes: bytes - 1
                ) != limited_text
            )
        ) | try expect_false
        stringify(rows: [[""]], options: options, max_bytes: 0) | try expect_equal(
            expected: limited_text
        )
        (
            (
                (
                    parse(
                        text: text,
                        options: options,
                        max_rows: 3,
                        max_cells: 3
                    ) | try expect_ok
                ) != rows
            )
        ) | try expect_false
        let limited_rows: Result[List[List[String]], CsvError] = error(
            CsvError.LimitExceeded
        )
        parse(text: text, options: options, max_rows: 2) | try expect_equal(
            expected: limited_rows
        )
        parse(text: text, options: options, max_cells: 2) | try expect_equal(
            expected: limited_rows
        )
        parse(text: "\"\"", options: options, max_rows: 0) | try expect_equal(
            expected: limited_rows
        )
        parse(text: "\"\"", options: options, max_cells: 0) | try expect_equal(
            expected: limited_rows
        )

test "CSV preserves whitespace and normalizes quoted CRLF":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let rows = [[" "], ["\t"], ["line\n\nbreak"], ["\""], ["", "", ""]]
    (
        (
            (
                parse(
                    text: (
                        stringify(
                            rows: rows,
                            options: options
                        ) | try expect_ok
                    ),
                    options: options
                ) | try expect_ok
            ) != rows
        )
    ) | try expect_false
    (
        (
            (
                parse(
                    text: "\"line\r\n\r\nbreak\"\r\n\"\"\r\n",
                    options: options
                ) | try expect_ok
            ) != [["line\n\nbreak"], [""]]
        )
    ) | try expect_false

test "CSV quotes delimiters multiline cells and line endings":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let rows = [["a,b", "say \"hi\"", "line\nbreak"], ["", "é", "last"]]
    let text = (stringify(rows: rows, options: options) | try expect_ok)
    parse(text: text, options: options, max_rows: 2, max_cells: 6) | try expect_ok | try expect_equal(
        expected: rows
    )
    let windows = CsvOptions(delimiter: ";", line_ending: "\r\n")
    stringify(rows: [["a", "b"]], options: windows) | try expect_ok | try expect_equal(
        expected: "a;b\r\n"
    )

test "CSV rejects malformed records invalid options and limits":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let malformed: Result[List[List[String]], CsvError] = error(CsvError.InvalidData)
    parse(text: "\"unterminated", options: options) | try expect_equal(
        expected: malformed
    )
    for text in ["\"\"x\n", "x\"\"\n", "\"\"\"\n"]:
        parse(text: text, options: options) | try expect_equal(expected: malformed)
    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    parse(text: "a,b\n", options: options, max_cells: 1) | try expect_equal(
        expected: limited
    )
    parse(text: "a\nb\n", options: options, max_rows: 1) | try expect_equal(
        expected: limited
    )
    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    (
        (
            stringify(
                rows: [["a"]],
                options: CsvOptions(delimiter: "::", line_ending: "\n")
            ) != invalid
        )
    ) | try expect_false
