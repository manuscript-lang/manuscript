import (
	Bytes, join from "@std/bytes.ms",
	ReadStream, Sink, Transform, WriteStream, through from "@std/io/io.ms",
	StringBuilder from "@std/string.ms",
)

// Delimiter and line ending used when parsing or writing CSV, and the row and cell
// bounds for `parse`.
export type CsvOptions:
	// One non-NUL ASCII delimiter other than quote, CR or LF; defaults to comma.
	delimiter: String = ","
	// Row terminator for encoding, either LF or CRLF; defaults to LF.
	line_ending: String = "\n"
	// Maximum rows `parse` returns; none adds no row budget.
	max_rows: Int? = none
	// Maximum cells `parse` returns across all rows; none adds no cell budget.
	max_cells: Int? = none

// A malformed-input error at the one-based line and character column of byte offset
// `at`.
fn invalid_at(bytes: Bytes, at: Int, reason: String) Error:
	var line = 1
	var start = 0

	for i in 0..at:
		if bytes[i] == 10:
			line += 1
			start = i + 1

	before := bytes.decode_utf8_range(start, at).get("")
	column := before.length() + 1
	return Error(
		"CSV {line}:{column}: {reason}",
		kind: "EBADMSG",
		details: {
			"line": line.to_string(),
			"column": column.to_string(),
			"reason": reason.clone()
		},
	)

// Parses CSV into rows of cells, using fresh default options when omitted.
// `options.max_rows` and `options.max_cells` bound large inputs.
export fn parse(text: String, options: CsvOptions = CsvOptions()) List[List[String]]!:
	rows_budget := budget(options.max_rows)
	cells_budget := budget(options.max_cells)
	if rows_budget < 0 or cells_budget < 0: return error(
		Error("CSV: invalid input", kind: "EINVAL")
	)

	valid := check_options(options)
	if valid.is_error(): return error(valid.err())

	bytes := text.to_bytes()
	total := bytes.length()
	var reader = Reader(
		bytes: bytes,
		total: total,
		delimiter: options.delimiter.scalar_values()[0].to_uint8().get(0),
		delimiter_text: options.delimiter.clone(),
		at: 0,
		quote: -1,
		delimiter_at: -1,
		line_at: -1,
	)
	var rows = List[List[String]]()
	var cells = 0

	while true:
		record := reader.read_record()
		if record.is_error(): return error(record.err())

		found := record.get()
		if found.is_none(): break

		row := found.get()
		if rows.length() >= rows_budget or row.length() > cells_budget - cells: return error(
			Error("CSV: limit exceeded", kind: "EOVERFLOW")
		)

		cells += row.length()
		rows.append(row.clone())

	return ok(rows)

// The budget as a count, with no budget as a very large one and a negative budget as
// -1.
fn budget(limit: Int?) Int:
	if value := limit: return value
	return 9223372036854775807

// Delimiter: one ASCII scalar other than quote, CR, LF or NUL. Line ending: LF or CRLF.
fn check_options(options: CsvOptions) Unit!:
	scalars := options.delimiter.scalar_values()
	if scalars.length() != 1: return error(Error("CSV: invalid input", kind: "EINVAL"))

	delimiter := scalars[0]
	if (
		delimiter == 0
		or delimiter >= 128
		or delimiter == 34
		or delimiter == 13
		or delimiter == 10
	): return error(Error("CSV: invalid input", kind: "EINVAL"))
	if options.line_ending != "\n" and options.line_ending != "\r\n": return error(
		Error("CSV: invalid input", kind: "EINVAL")
	)

// The input as bytes with a cursor. The cached offsets are the next quote, delimiter
// and LF at or after the cursor, or total when there is none; they are searched again
// only once passed.
type Reader:
	bytes: Bytes
	total: Int
	delimiter: UInt8
	delimiter_text: String
	at: Int
	quote: Int
	delimiter_at: Int
	line_at: Int

fn var Reader.next_quote(from: Int) Int:
	if self.quote < from: self.quote = self.bytes.index_of_byte(34, from).get(
		self.total
	)
	return self.quote

fn var Reader.next_delimiter(from: Int) Int:
	if self.delimiter_at < from: self.delimiter_at = self.bytes.index_of_byte(
		self.delimiter,
		from,
	).get(self.total)
	return self.delimiter_at

fn var Reader.next_line(from: Int) Int:
	if self.line_at < from: self.line_at = self.bytes.index_of_byte(10, from).get(
		self.total
	)
	return self.line_at

fn Reader.text_between(start: Int, end: Int) String:
	if text := self.bytes.decode_utf8_range(start, end): return text
	return ""

// The offset just past the line ending at the cursor, or the cursor when the cursor
// is not at one.
fn Reader.line_end_after(at: Int) Int:
	if at >= self.total: return at

	byte := self.bytes[at]
	if byte == 10: return at + 1
	if byte == 13 and at + 1 >= self.total: return at + 1
	if byte == 13 and self.bytes[at + 1] == 10: return at + 2

	return at

// Reads the next record, skipping empty lines; none at end of input.
fn var Reader.read_record() List[String]?!:
	while true:
		skipped := self.line_end_after(self.at)
		if skipped == self.at: break

		self.at = skipped

	if self.at >= self.total: return ok(none)

	// A line without quotes is one record whose cells are the delimiter-separated
	// pieces.
	line := self.next_line(self.at)

	if self.next_quote(self.at) > line:
		var last = line
		if last > self.at and self.bytes[last - 1] == 13: last -= 1

		text := self.text_between(self.at, last)
		self.at = line
		if line < self.total: self.at = line + 1
		return ok(text.split(self.delimiter_text).clone())

	var row = List[String]()

	while true:
		var cell = ""
		var at = self.at.to_int()

		if at < self.total and self.bytes[at] == 34:
			at += 1

			start := at
			var first_escape = -1
			var multiple_escapes = false

			while true:
				close := self.next_quote(at)
				if close >= self.total: return error(
					invalid_at(
						self.bytes,
						self.at.to_int(),
						"unterminated quoted cell",
					)
				)

				at = close + 1

				if at < self.total and self.bytes[at] == 34:
					if first_escape < 0: first_escape = close
					else: multiple_escapes = true

					at += 1
					continue

				break

			if first_escape >= 0 and not multiple_escapes:
				prefix := self.text_between(start, first_escape)
				suffix := self.text_between(first_escape + 2, at - 1)
				cell = "{prefix}\"{suffix}"
			else:
				cell = self.text_between(start, at - 1)
				if multiple_escapes: cell = cell.replace("\"\"", "\"")

			if cell.contains("\r\n"): cell = cell.replace("\r\n", "\n")

			ended := self.line_end_after(at)

			if at >= self.total or ended > at:
				row.append(cell)
				self.at = ended
				return ok(row)

			if self.bytes[at] != self.delimiter: return error(
				invalid_at(
					self.bytes,
					at,
					"expected a delimiter or line end after the closing quote",
				)
			)

			row.append(cell)
			self.at = at + 1
			continue

		stop := self.next_delimiter(at)
		newline := self.next_line(at)
		end := if newline < stop: newline else: stop
		quote := self.next_quote(at)
		if quote < end: return error(
			invalid_at(self.bytes, quote, "quote inside an unquoted cell")
		)

		if end < stop or stop >= self.total:
			// The cell closes the record; drop the CR of a CRLF ending.
			var last = end
			if last > at and self.bytes[last - 1] == 13: last -= 1
			row.append(self.text_between(at, last))
			self.at = end
			if end < self.total: self.at = end + 1
			return ok(row)

		row.append(self.text_between(at, end))
		self.at = end + 1

// Cuts a byte stream at the line ends outside quotes and parses each complete block of
// records with `parse`.
// `pending` holds the already-scanned fragments of the unfinished record; `quoted` says whether
// that scan ended inside a quoted cell. Fragments are joined only at a record boundary
// or EOF.
type CsvRows:
	options: CsvOptions
	max_record_bytes: Int?
	pending: List[Bytes]
	pending_size: Int
	quoted: Bool
	// The longest complete record the last `boundary` call passed, without its line
	// feed.
	longest: Int

// Offset just past the last line end outside quotes in `data`, or 0 when the block
// holds none.
fn var CsvRows.boundary(data: Bytes) Int:
	total := data.length()
	var pos = 0
	var cut = 0
	var previous = self.pending_size
	self.longest = 0

	var quote = data.index_of_byte(34, pos).get(total)
	var line = data.index_of_byte(10, pos).get(total)

	while pos < total:
		if self.quoted:
			if quote >= total: break

			self.quoted = false
			pos = quote + 1
			quote = data.index_of_byte(34, pos).get(total)
			continue

		if line < pos: line = data.index_of_byte(10, pos).get(total)
		if quote < pos: quote = data.index_of_byte(34, pos).get(total)

		if line < quote:
			size := previous + line - cut
			if size > self.longest: self.longest = size
			previous = 0
			cut = line + 1
			pos = line + 1
			continue

		if quote >= total: break

		self.quoted = true
		pos = quote + 1
		quote = data.index_of_byte(34, pos).get(total)

	return cut

fn CsvRows.check_size(size: Int) Unit!:
	if limit := self.max_record_bytes:
		if size > limit: return error(Error("CSV: limit exceeded", kind: "EOVERFLOW"))

fn var CsvRows.step(value: Bytes, var out: List[List[String]]) Unit!:
	cut := self.boundary(value)
	rest := value.length() - cut
	size := if cut == 0: self.pending_size + rest else: rest

	if cut == 0:
		if not value.is_empty(): self.pending.append(value)
		self.pending_size = size
		self.check_size(self.longest)?
		return self.check_size(size)

	var data = value
	var end = cut

	if self.pending_size > 0:
		self.pending.append(data)
		data = join(self.pending)
		end += self.pending_size

	self.pending = []
	self.pending_size = rest
	if rest > 0: self.pending.append(data.slice(end, data.length())?)
	self.check_size(self.longest)?
	self.check_size(size)?

	decoded := data.decode_utf8_range(0, end)
	if decoded.is_none(): return invalid_text()

	text := decoded.get("")
	return write_rows(parse(text, self.options)?, var out)

fn var CsvRows.finish(var out: List[List[String]]) Unit!:
	data := join(self.pending)
	self.pending = []
	self.pending_size = 0
	if data.is_empty(): return check_options(self.options)

	self.check_size(data.length())?

	decoded := data.decode_utf8()
	if decoded.is_none(): return invalid_text()

	text := decoded.get("")
	return write_rows(parse(text, self.options)?, var out)

fn invalid_text() Unit!:
	return error(Error("CSV: invalid UTF-8", kind: "EBADMSG"))

fn write_rows(rows: List[List[String]], var out: List[List[String]]) Unit!:
	for row in rows: out.append(row)

/*
Reads CSV rows from a byte stream, one `List[String]` per record, with the cells `parse` returns.

Chunks may end anywhere, including inside a quoted cell, a CRLF or a UTF-8 scalar; only the unfinished
record is buffered. `options.max_rows` and `options.max_cells` bound `parse` only and are ignored here,
so the result never depends on chunk boundaries; `max_record_bytes` bounds that record and fails the read with `EOVERFLOW`. A
malformed record fails the read with `EBADMSG`, and invalid `options` with `EINVAL`. Closing the
result closes `input`.
*/
export fn csv_rows(
	input: ReadStream[Bytes],
	options: CsvOptions = CsvOptions(),
	max_record_bytes: Int? = none,
) ReadStream[List[String]]:
	return through[Bytes, List[String]](
		input,
		CsvRows(
			options: CsvOptions(
				delimiter: options.delimiter,
				line_ending: options.line_ending,
			),
			max_record_bytes: max_record_bytes,
			pending: [],
			pending_size: 0,
			quoted: false,
			longest: 0,
		),
	)

// Encodes rows as CSV with comma delimiters and LF endings by default.
// Quotes cells when required by the delimiter or line ending.
export fn stringify(
	rows: List[List[String]],
	options: CsvOptions = CsvOptions(),
	max_bytes: Int? = none,
) String!:
	limit := budget(max_bytes)
	if limit < 0: return error(Error("CSV: invalid input", kind: "EINVAL"))

	valid := check_options(options)
	if valid.is_error(): return error(valid.err())

	var out = StringBuilder()
	var used = 0
	crlf := options.line_ending == "\r\n"
	delimiter := options.delimiter.clone()

	for row in rows:
		var line = ""

		if row.length() == 1 and row[0] == "":
			line = "\"\""
		else:
			var pieces = List[String]()
			for field in row:
				pieces.append(encode_field(field, delimiter, crlf))
			line = pieces.join(options.delimiter)

		line = "{line}{options.line_ending}"

		size := line.byte_length()
		if size > limit - used: return error(
			Error("CSV: limit exceeded", kind: "EOVERFLOW")
		)

		used += size
		out.append(line)

	return ok(out.build())

fn needs_quotes(field: String, delimiter: String) Bool:
	if field.is_empty(): return false
	if (
		field.contains("\"")
		or field.contains("\r")
		or field.contains("\n")
		or field.contains(delimiter)
	): return true

	first := field.scalar_at(0)
	if first <= 32 or first >= 127: return field.get(0).trim() == ""

	return field == "\\."

fn replaced(text: String, old: String, new: String) String:
	return text.replace(old, new)

fn encode_field(field: String, delimiter: String, crlf: Bool) String:
	if not needs_quotes(field, delimiter): return field.clone()

	var quoted = replaced(field, "\"", "\"\"")
	if crlf: quoted = replaced(replaced(quoted, "\r\n", "\n"), "\n", "\r\n")
	return "\"{quoted}\""

// A sink that encodes each row as `stringify` does and puts the bytes into `output`.
type CsvRowsSink:
	output: WriteStream[Bytes]
	options: CsvOptions

fn var CsvRowsSink.write(value: List[String]) Unit!:
	text := stringify([value], self.options)?
	return self.output.write(text.to_bytes())

fn var CsvRowsSink.flush() Unit!:
	return self.output.flush()

fn var CsvRowsSink.close() Unit!:
	return self.output.close()

/*
Writes rows to a byte stream, each as `stringify` encodes it (quoting cells that need it, ending with the
options' line ending). Invalid `options` fail the first write with `EINVAL`. Writes delegate to `output`'s sink, which may wait.
`flush().wait()` uses that sink's completion condition; a pipe may retain up to capacity unread values. Closing the result closes `output`.
*/
export fn csv_writer(
	output: WriteStream[Bytes],
	options: CsvOptions = CsvOptions(),
) WriteStream[List[String]]:
	return WriteStream[List[String]](CsvRowsSink(output: output, options: options))
