import {parse, stringify, CsvOptions, CsvError} from "@std/csv.ms"
import panic from "@std/faults.ms"

test "CSV retains single empty fields and distinguishes empty rows":
    for ending in ["\n", "\r\n"]:
        for delimiter in [",", ";", "\t"]:
            let options = CsvOptions(delimiter, ending)
            let rows = [["a"], [""], ["b"], [""], [""]]
            let expected = "a{ending}\"\"{ending}b{ending}\"\"{ending}\"\"{ending}"
            let text = try stringify(rows, options)
            if text != expected: return panic("single empty field encoding")
            if (try parse(text, options)) != rows: return panic(
                "single empty field roundtrip"
            )

            let empty_rows: List[List[String]] = [[], []]
            if ((try stringify(empty_rows, options)) != "{ending}{ending}"):
                return panic("empty rows encoding")

            let no_rows: List[List[String]] = []
            if (try parse("{ending}{ending}", options)) != no_rows:
                return panic("blank lines are skipped")
            if (
                (
                    try parse(
                        "{ending}\"\"{ending}{ending}\"\"",
                        options
                    )
                ) != [[""], [""]]
            ):
                return panic(
                    "quoted empty fields with blank lines and no final terminator"
                )
            if ((try stringify([["", ""]], options)) != "{delimiter}{ending}"):
                return panic("multiple empty cells encoding")

test "CSV quoted empty fields respect exact row cell and byte budgets":
    for ending in ["\n", "\r\n"]:
        let options = CsvOptions(",", ending)
        let rows = [[""], ["a"], [""]]
        let text = "\"\"{ending}a{ending}\"\"{ending}"
        let bytes = text.byte_length()
        if (try stringify(rows, options, bytes)) != text:
            return panic("exact quoted output budget")

        let limited_text: Result[String, CsvError] = error(CsvError.LimitExceeded)
        if (stringify(rows, options, bytes - 1) != limited_text):
            return panic("quotes and terminators count toward output budget")
        if stringify([[""]], options, 0) != limited_text:
            return panic("zero quoted output budget")
        if ((try parse(text, options, 3, 3)) != rows):
            return panic("exact quoted row and cell budgets")

        let limited_rows: Result[List[List[String]], CsvError] = error(
            CsvError.LimitExceeded
        )
        if parse(text, options, 2) != limited_rows:
            return panic("quoted empty row counts")
        if parse(text, options, max_cells: 2) != limited_rows:
            return panic("quoted empty cell counts")
        if parse("\"\"", options, 0) != limited_rows:
            return panic("zero quoted row budget")
        if parse("\"\"", options, max_cells: 0) != limited_rows:
            return panic("zero quoted cell budget")

test "CSV preserves whitespace and normalizes quoted CRLF":
    let options = CsvOptions(",", "\n")
    let rows = [[" "], ["\t"], ["line\n\nbreak"], ["\""], ["", "", ""]]
    if ((try parse(try stringify(rows, options), options)) != rows):
        return panic("whitespace and quoted multiline roundtrip")
    if (
        (try parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options)) != [
            ["line\n\nbreak"],
            [""]
        ]
    ):
        return panic("quoted CRLF normalization")

test "CSV quotes delimiters multiline cells and line endings":
    let options = CsvOptions(",", "\n")
    let rows = [["a,b", "say \"hi\"", "line\nbreak"], ["", "é", "last"]]
    let text = try stringify(rows, options)
    if ((try parse(text, options, 2, 6)) != rows): return panic("quoted CSV roundtrip")

    let windows = CsvOptions(";", "\r\n")
    if (try stringify([["a", "b"]], windows)) != "a;b\r\n": return panic(
        "delimiter and CRLF"
    )

test "CSV rejects malformed records invalid options and limits":
    let options = CsvOptions(",", "\n")
    let malformed: Result[List[List[String]], CsvError] = error(CsvError.InvalidData)
    if parse("\"unterminated", options) != malformed: return panic("unclosed quote")

    for text in ["\"\"x\n", "x\"\"\n", "\"\"\"\n"]:
        if parse(text, options) != malformed: return panic("malformed quoting")
    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    if parse("a,b\n", options, max_cells: 1) != limited: return panic("cell budget")
    if parse("a\nb\n", options, 1) != limited: return panic("row budget")

    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    if (stringify([["a"]], CsvOptions("::", "\n")) != invalid): return panic(
        "invalid delimiter"
    )
