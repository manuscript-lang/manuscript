import {parse, stringify, CsvOptions, CsvError} from "@std/csv.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "CSV quotes delimiters multiline cells and line endings":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let rows = [
        ["a,b", "say \"hi\"", "line\nbreak"],
        ["", "é", "last"]
    ]
    let text = value(stringify(rows: rows, options: options))
    if (
        value(
            parse(
                text: text,
                options: options,
                max_rows: 2,
                max_cells: 6
            )
        ) != rows
    ): return panic("quoted CSV roundtrip")

    let windows = CsvOptions(delimiter: ";", line_ending: "\r\n")
    if value(
        stringify(
            rows: [
                ["a", "b"]
            ],
            options: windows
        )
    ) != "a;b\r\n": return panic("delimiter and CRLF")

test "CSV rejects malformed records invalid options and limits":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let malformed: Result[List[List[String]], CsvError] = error(
        CsvError.InvalidData
    )
    if parse(text: "\"unterminated", options: options) != malformed: return panic(
        "unclosed quote"
    )

    let limited: Result[List[List[String]], CsvError] = error(
        CsvError.LimitExceeded
    )
    if parse(
        text: "a,b\n",
        options: options,
        max_cells: 1
    ) != limited: return panic("cell budget")
    if parse(
        text: "a\nb\n",
        options: options,
        max_rows: 1
    ) != limited: return panic("row budget")

    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    if (
        stringify(
            rows: [
                ["a"]
            ],
            options: CsvOptions(delimiter: "::", line_ending: "\n")
        ) != invalid
    ): return panic("invalid delimiter")

test "CSV single empty cell rows survive a round trip":
    let options = CsvOptions(delimiter: ",", line_ending: "\n")
    let rows = [["a"], [""], ["b"]]
    let text = value(stringify(rows: rows, options: options))
    if text != "a\n\"\"\nb\n": return panic("quoted sole empty cell")
    if value(parse(text: text, options: options)) != rows: return panic(
        "single column round trip"
    )

    let crlf = CsvOptions(delimiter: ",", line_ending: "\r\n")
    if value(stringify(rows: [[""]], options: crlf)) != "\"\"\r\n": return panic(
        "CRLF empty cell"
    )
    if (
        value(parse(text: "a,b\n\n\nc,d\n", options: options)) != [
            ["a", "b"],
            ["c", "d"]
        ]
    ): return panic("blank lines skipped")
