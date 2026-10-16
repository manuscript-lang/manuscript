package msruntime

import (
	"encoding/csv"
	"io"
	"strings"
	"unicode"
	"unicode/utf8"
)

func csvOptions(o *CsvOptions) (rune, bool, bool) {
	if o == nil {
		return ',', false, true
	}
	s, ending := o.Delimiter, o.LineEnding
	if len(s) != 1 || s[0] >= 128 || strings.ContainsAny(s, "\"\r\n\x00") || ending != "\n" && ending != "\r\n" {
		return 0, false, false
	}
	return rune(s[0]), ending == "\r\n", true
}

// Csv_Parse reads CSV records with the given options and optional row and
// cell budgets. Rows may have different widths and blank lines are skipped.
func Csv_Parse(ctx *Execution, text string, options *CsvOptions, maxRows, maxCells Option[int]) Result[*List[*List[string]], CsvError] {
	delimiter, _, ok := csvOptions(options)
	rows, cells := dfBudget(maxRows), dfBudget(maxCells)
	if !ok || rows < 0 || cells < 0 {
		return Fail[*List[*List[string]], CsvError](CsvError_InvalidInput{})
	}
	reader := csv.NewReader(strings.NewReader(text))
	reader.Comma = delimiter
	reader.FieldsPerRecord = -1
	values := []*List[string]{}
	count := 0
	for {
		CheckCancelled(ctx)
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return Fail[*List[*List[string]], CsvError](CsvError_InvalidData{})
		}
		if len(values) >= rows || len(record) > cells-count {
			return Fail[*List[*List[string]], CsvError](CsvError_LimitExceeded{})
		}
		count += len(record)
		values = append(values, NewList(record...))
	}
	return Ok[*List[*List[string]], CsvError](NewList(values...))
}

// Csv_Stringify encodes rows, ending every row with the selected terminator.
// A row holding one empty cell is quoted so that it survives a round trip.
func Csv_Stringify(ctx *Execution, rows *List[*List[string]], options *CsvOptions, maxBytes Option[int]) Result[string, CsvError] {
	delimiter, crlf, ok := csvOptions(options)
	n := dfBudget(maxBytes)
	if !ok || n < 0 {
		return Fail[string, CsvError](CsvError_InvalidInput{})
	}
	w := &dfLimitedWriter{max: n}
	ending := "\n"
	if crlf {
		ending = "\r\n"
	}
	for _, row := range rows.Items {
		CheckCancelled(ctx)
		record := append([]string{}, row.Items...)
		if len(record) == 1 && record[0] == "" {
			record[0] = "\"\""
		} else {
			for i, field := range record {
				record[i] = csvField(field, delimiter, crlf)
			}
		}
		line := strings.Join(record, string(delimiter)) + ending
		if _, err := w.Write([]byte(line)); err != nil {
			return Fail[string, CsvError](CsvError_LimitExceeded{})
		}
	}
	return Ok[string, CsvError](w.String())
}

// csvField quotes a cell when the reader could not otherwise recover it.
// Unlike encoding/csv's writer, a lone carriage return stays in a quoted cell
// in CRLF mode.
func csvField(field string, delimiter rune, crlf bool) string {
	if field == "" {
		return field
	}
	first, _ := utf8.DecodeRuneInString(field)
	if field != `\.` && !strings.ContainsAny(field, "\"\r\n"+string(delimiter)) && !unicode.IsSpace(first) {
		return field
	}
	field = strings.ReplaceAll(field, "\"", "\"\"")
	if crlf {
		field = strings.ReplaceAll(strings.ReplaceAll(field, "\r\n", "\n"), "\n", "\r\n")
	}
	return "\"" + field + "\""
}

// Errors_Message_CsvError returns the fixed CSV diagnostic.
func Errors_Message_CsvError(_ *Execution, e CsvError) string {
	switch e.(type) {
	case CsvError_InvalidInput:
		return dfMessage("CSV", reasonInvalidInput)
	case CsvError_InvalidData:
		return dfMessage("CSV", reasonInvalidData)
	case CsvError_LimitExceeded:
		return dfMessage("CSV", reasonLimitExceeded)
	}
	return dfMessage("CSV", "operation failed")
}
