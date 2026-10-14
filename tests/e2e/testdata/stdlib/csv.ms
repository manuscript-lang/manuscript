import {parse, stringify, CsvOptions, CsvError} from "@std/csv.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "CSV retains single empty fields and distinguishes empty rows":
    for ending in ["\n", "\r\n"]:
        for delimiter in [",", ";", "\t"]:
            let options = CsvOptions(delimiter: delimiter, line_ending: ending)
            let rows = [["a"], [""], ["b"], [""], [""]]
            let expected = "a{ending}\"\"{ending}b{ending}\"\"{ending}\"\"{ending}"
            let text = value(stringify(rows: rows, options: options))
            if text != expected: return panic("single empty field encoding")
            if value(parse(text: text, options: options)) != rows: return panic(
                "single empty field roundtrip"
            )

            let empty_rows: List[List[String]] = [[], []]
            if (
                value(
                    stringify(rows: empty_rows, options: options)
                ) != "{ending}{ending}"
            ):
                return panic("empty rows encoding")

            let no_rows: List[List[String]] = []
            if value(parse(text: "{ending}{ending}", options: options)) != no_rows:
                return panic("blank lines are skipped")
            if (
                value(
                    parse(
                        text: "{ending}\"\"{ending}{ending}\"\"",
                        options: options
                    )
                ) != [[""], [""]]
            ):
                return panic(
                    "quoted empty fields with blank lines and no final terminator"
                )
            if (
                value(
                    stringify(rows: [["", ""]], options: options)
                ) != "{delimiter}{ending}"
            ):
                return panic("multiple empty cells encoding")

test "CSV quoted empty fields respect exact row cell and byte budgets":
    for ending in ["\n", "\r\n"]:
        let options = CsvOptions(delimiter: ",", line_ending: ending)
        let rows = [[""], ["a"], [""]]
        let text = "\"\"{ending}a{ending}\"\"{ending}"
        let bytes = text.byte_length()
        if value(stringify(rows: rows, options: options, max_bytes: bytes)) != text:
            return panic("exact quoted output budget")

        let limited_text: Result[String, CsvError] = error(CsvError.LimitExceeded)
        if (
            stringify(
                rows: rows,
                options: options,
                max_bytes: bytes - 1
            ) != limited_text
        ):
            return panic("quotes and terminators count toward output budget")
        if stringify(rows: [[""]], options: options, max_bytes: 0) != limited_text:
            return panic("zero quoted output budget")
        if (
            value(
                parse(
                    text: text,
                    options: options,
                    max_rows: 3,
                    max_cells: 3
                )
            ) != rows
        ):
            return panic("exact quoted row and cell budgets")

        let limited_rows: Result[List[List[String]], CsvError] = error(
            CsvError.LimitExceeded
        )
        if parse(text: text, options: options, max_rows: 2) != limited_rows:
            return panic("quoted empty row counts")
        if parse(text: text, options: options, max_cells: 2) != limited_rows:
            return panic("quoted empty cell counts")
        if parse(text: "\"\"", options: options, max_rows: 0) != limited_rows:
            return panic("zero quoted row budget")
        if parse(text: "\"\"", options: options, max_cells: 0) != limited_rows:
            return panic("zero quoted cell budget")

test "CSV preserves whitespace and normalizes quoted CRLF":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let rows = [[" "], ["\t"], ["line\n\nbreak"], ["\""], ["", "", ""]]
    if (
        value(
            parse(
                text: value(stringify(rows: rows, options: options)),
                options: options
            )
        ) != rows
    ):
        return panic("whitespace and quoted multiline roundtrip")
    if (
        value(
            parse(
                text: "\"line\r\n\r\nbreak\"\r\n\"\"\r\n",
                options: options
            )
        ) != [["line\n\nbreak"], [""]]
    ):
        return panic("quoted CRLF normalization")

test "CSV quotes delimiters multiline cells and line endings":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let rows = [["a,b", "say \"hi\"", "line\nbreak"], ["", "é", "last"]]
    let text = value(stringify(rows: rows, options: options))
    if (value(parse(text: text, options: options, max_rows: 2, max_cells: 6)) != rows): return panic(
        "quoted CSV roundtrip"
    )

    let windows = CsvOptions(delimiter: ";", line_ending: "\r\n")
    if value(stringify(rows: [["a", "b"]], options: windows)) != "a;b\r\n": return panic(
        "delimiter and CRLF"
    )

test "CSV rejects malformed records invalid options and limits":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let malformed: Result[List[List[String]], CsvError] = error(CsvError.InvalidData)
    if parse(text: "\"unterminated", options: options) != malformed: return panic(
        "unclosed quote"
    )

    for text in ["\"\"x\n", "x\"\"\n", "\"\"\"\n"]:
        if parse(text: text, options: options) != malformed: return panic(
            "malformed quoting"
        )

    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    if parse(text: "a,b\n", options: options, max_cells: 1) != limited: return panic(
        "cell budget"
    )
    if parse(text: "a\nb\n", options: options, max_rows: 1) != limited: return panic(
        "row budget"
    )

    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    if (
        stringify(
            rows: [["a"]],
            options: CsvOptions(delimiter: "::", line_ending: "\n")
        ) != invalid
    ): return panic("invalid delimiter")
