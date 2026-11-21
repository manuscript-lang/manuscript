// ms: allow_effect std.clock.read

import (
	Bytes, join from "@std/bytes.ms",
	ReadStream, WriteStream, through from "@std/io/io.ms",
	StringBuilder from "@std/string_builder.ms",
)

// Delimiter and line ending for parsing or writing CSV, and the row and cell bounds
// for `parse`. Invalid values return an `Error` with kind `EINVAL`.
export type CsvOptions:
	// One ASCII delimiter other than NUL, quote, CR or LF; defaults to comma.
	delimiter: String = ","
	// Row terminator when writing, either LF or CRLF; defaults to LF. Parsing accepts
	// both.
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

	before := bytes.decode_utf8_range(start, at).get_or("")
	column := before.scalar_length() + 1
	return Error(
		f"CSV {line}:{column}: {reason}",
		kind: "EBADMSG",
		details: {
			"line": line.to_string(),
			"column": column.to_string(),
			"reason": reason.clone()
		},
	)

// A reader over `text`, or the error of invalid options.
fn open_reader(text: String, options: CsvOptions) Reader!:
	valid := check_options(options)
	if valid.is_error(): return error(valid.err())

	bytes := text.to_bytes()
	total := bytes.length()
	return ok(
		Reader(
			text: text.clone(),
			bytes: bytes,
			total: total,
			delimiter: options.delimiter.scalar_values()[
				0
			].to_uint8().get_or(0),
			delimiter_text: options.delimiter.clone(),
			at: 0,
			quote: -1,
			delimiter_at: -1,
			line_at: -1,
		)
	)

// Parses CSV into rows of cells. Empty lines are skipped, and a quoted cell may hold
// the delimiter, quotes (written `""`) and line breaks. `options.max_rows` and
// `options.max_cells` bound large inputs and return `EOVERFLOW` when exceeded. Malformed
// input returns an `Error` with kind `EBADMSG`, the line and column in `details`.
// A CRLF inside a quoted cell reads as LF, so a cell holds one newline spelling
// whatever the file's line ending was.
export fn parse(text: String, options: CsvOptions = CsvOptions()) List[List[String]]!:
	rows_budget := budget(options.max_rows)
	cells_budget := budget(options.max_cells)
	if rows_budget < 0 or cells_budget < 0: return error(
		Error("CSV: invalid input", kind: "EINVAL")
	)

	var reader = open_reader(text, options)?
	var rows = List[List[String]]()
	var cells = 0
	var row = List[String]()

	while true:
		row = []

		record := reader.read_record(
			rows.length(),
			fn r,
			c,
			cell: row.append(cell.clone())
		)
		if record.is_error(): return error(record.err())

		found := record.get()
		if found.is_none(): break
		if rows.length() >= rows_budget or row.length() > cells_budget - cells: return error(
			Error("CSV: limit exceeded", kind: "EOVERFLOW")
		)

		cells += row.length()
		rows.append(row.clone())

	return ok(rows)

// Calls `f(row, column, cell)` for every cell of `text`, in order, without building
// rows. Rows and columns count from zero. A cell is a view of `text` that is valid only
// during the call (clone it to keep it), except that a quoted cell holding escapes is a
// fresh text. `options` and errors are as for `parse`; malformed input fails after the
// cells before it were visited.
export fn each_cell(
	text: String,
	f: fn(Int, Int, String) Void,
	options: CsvOptions = CsvOptions()
) Void!:
	rows_budget := budget(options.max_rows)
	cells_budget := budget(options.max_cells)
	if rows_budget < 0 or cells_budget < 0: return error(
		Error("CSV: invalid input", kind: "EINVAL")
	)

	var reader = open_reader(text, options)?
	var rows = 0
	var cells = 0

	while true:
		record := reader.read_record(rows, f)
		if record.is_error(): return error(record.err())

		found := record.get()
		if found.is_none(): break

		count := found.get_or(0)
		if rows >= rows_budget or count > cells_budget - cells: return error(
			Error("CSV: limit exceeded", kind: "EOVERFLOW")
		)

		cells += count
		rows += 1

	return ok()

// The budget as a count: no budget is the largest `Int`, and a negative budget stays
// negative.
fn budget(limit: Int?) Int:
	if value := limit: return value
	return 9223372036854775807

// Delimiter: one ASCII scalar other than quote, CR, LF or NUL. Line ending: LF or CRLF.
fn check_options(options: CsvOptions) Void!:
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
	text: String
	bytes: Bytes
	total: Int
	delimiter: UInt8
	delimiter_text: String
	at: Int
	quote: Int
	delimiter_at: Int
	line_at: Int

fn var Reader.next_quote(from: Int) Int:
	if self.quote < from: self.quote = self.bytes.index_of_byte(34, from).get_or(
		self.total
	)
	return self.quote

fn var Reader.next_delimiter(from: Int) Int:
	if self.delimiter_at < from: self.delimiter_at = self.bytes.index_of_byte(
		self.delimiter,
		from,
	).get_or(self.total)
	return self.delimiter_at

fn var Reader.next_line(from: Int) Int:
	if self.line_at < from: self.line_at = self.bytes.index_of_byte(10, from).get_or(
		self.total
	)
	return self.line_at

// The offset just past the line ending at the cursor, or the cursor when the cursor
// is not at one.
fn Reader.line_end_after(at: Int) Int:
	if at >= self.total: return at

	byte := self.bytes[at]
	if byte == 10: return at + 1
	if byte == 13 and at + 1 >= self.total: return at + 1
	if byte == 13 and self.bytes[at + 1] == 10: return at + 2

	return at

// Reads the next record, skipping empty lines, and hands each cell to `f` as (row,
// column, cell): a view of the input where the cell is plain, an owned text where
// quotes were unescaped. Returns the cell count, or none at end of input.
fn var Reader.read_record(row: Int, f: fn(Int, Int, String) Void) Int?!:
	while true:
		skipped := self.line_end_after(self.at)
		if skipped == self.at: break

		self.at = skipped

	if self.at >= self.total: return ok(none)

	var col = 0

	// A line without quotes is one record whose cells are the delimiter-separated
	// pieces.
	line := self.next_line(self.at)

	if self.next_quote(self.at) > line:
		var last = line
		if last > self.at and self.bytes[last - 1] == 13: last -= 1

		var start = self.at

		while true:
			stop := self.next_delimiter(start)

			if stop >= last:
				f(row, col, self.text.view(start, last))
				col += 1
				break

			f(row, col, self.text.view(start, stop))
			col += 1
			start = stop + 1

		self.at = line
		if line < self.total: self.at = line + 1
		return ok(col)

	while true:
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

			var cell = self.text.view(start, at - 1).clone()

			if first_escape >= 0 and not multiple_escapes:
				prefix := self.text.view(start, first_escape)
				suffix := self.text.view(first_escape + 2, at - 1)
				cell = f"{prefix}\"{suffix}"
			else if multiple_escapes: cell = cell.replace("\"\"", "\"")

			if cell.contains("\r\n"): cell = cell.replace("\r\n", "\n")

			ended := self.line_end_after(at)

			if at >= self.total or ended > at:
				f(row, col, cell)
				self.at = ended
				return ok(col + 1)

			if self.bytes[at] != self.delimiter: return error(
				invalid_at(
					self.bytes,
					at,
					"expected a delimiter or line end after the closing quote",
				)
			)

			f(row, col, cell)
			col += 1
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
			f(row, col, self.text.view(at, last))
			self.at = end
			if end < self.total: self.at = end + 1
			return ok(col + 1)

		f(row, col, self.text.view(at, end))
		col += 1
		self.at = end + 1

// Cuts a byte stream at the line ends outside quotes and parses each complete block of
// records with `parse`.
// `pending` holds the already-scanned fragments of the unfinished record; `quoted` says whether
// that scan ended inside a quoted cell. Fragments are joined only at a record boundary
// or EOF.
type CsvRows:
	options: CsvOptions
	pending: List[Bytes]
	pending_size: Int
	quoted: Bool
	// The longest complete record the last `boundary` call passed, without its line
	// feed.
	longest: Int
	max_record_bytes: Int?

// Offset just past the last line end outside quotes in `data`, or 0 when the block
// holds none.
fn var CsvRows.boundary(data: Bytes) Int:
	total := data.length()
	var pos = 0
	var cut = 0
	var previous = self.pending_size
	self.longest = 0

	var quote = data.index_of_byte(34, pos).get_or(total)
	var line = data.index_of_byte(10, pos).get_or(total)

	while pos < total:
		if self.quoted:
			if quote >= total: break

			self.quoted = false
			pos = quote + 1
			quote = data.index_of_byte(34, pos).get_or(total)
			continue

		if line < pos: line = data.index_of_byte(10, pos).get_or(total)
		if quote < pos: quote = data.index_of_byte(34, pos).get_or(total)

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
		quote = data.index_of_byte(34, pos).get_or(total)

	return cut

fn CsvRows.check_size(size: Int) Void!:
	if limit := self.max_record_bytes:
		if size > limit: return error(Error("CSV: limit exceeded", kind: "EOVERFLOW"))

fn var CsvRows.step(move value: Bytes, var out: List[List[String]]) Void!:
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

	text := decoded.get_or("")
	return write_rows(parse(text, self.options)?, out)

fn var CsvRows.finish(var out: List[List[String]]) Void!:
	data := join(self.pending)
	self.pending = []
	self.pending_size = 0
	if data.is_empty(): return check_options(self.options)

	self.check_size(data.length())?

	decoded := data.decode_utf8()
	if decoded.is_none(): return invalid_text()

	text := decoded.get_or("")
	return write_rows(parse(text, self.options)?, out)

fn invalid_text() Void!:
	return error(Error("CSV: invalid UTF-8", kind: "EBADMSG"))

fn write_rows(rows: List[List[String]], var out: List[List[String]]) Void!:
	for row in rows: out.append(row)

/*
Reads CSV rows from a byte stream, one `List[String]` per record, with the cells `parse` returns.

Chunks may end anywhere, including inside a quoted cell, a CRLF or a UTF-8 scalar; only the
unfinished record is buffered. `options.max_rows` and `options.max_cells` are ignored here, so
the result never depends on chunk boundaries. Use `max_record_bytes` to bound the buffered
record; exceeding it fails the read with `EOVERFLOW`. A malformed record fails the read with
`EBADMSG`, and invalid `options` with `EINVAL`. Closing the result closes `input`.
*/
export fn csv_rows(
	move input: ReadStream[Bytes],
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

// Encodes rows as CSV, with comma delimiters and LF endings by default. A cell is
// quoted only when it needs it, for example when it holds the delimiter, a quote or a
// line break. Every row, including the last, ends with the line ending. `max_bytes`
// bounds the output and returns `EOVERFLOW` when exceeded.
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
	delimiter_size := delimiter.length()
	ending_size := options.line_ending.length()

	for row in rows:
		if row.length() == 1 and row[0] == "":
			out.append("\"\"")
			used += 2
		else:
			var first = true

			for field in row:
				if not first:
					out.append(delimiter)
					used += delimiter_size

				first = false

				if not needs_quotes(field, delimiter):
					out.append(field)
					used += field.length()
				else:
					quoted := quote_field(field, crlf)
					out.append(quoted)
					used += quoted.length()

		out.append(options.line_ending)
		used += ending_size
		if used > limit: return error(Error("CSV: limit exceeded", kind: "EOVERFLOW"))

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
	if first <= 32 or first >= 127: return field.chars()[0].trim() == ""

	return field == "\\."

fn replaced(text: String, old: String, new: String) String:
	return text.replace(old, new)

fn quote_field(field: String, crlf: Bool) String:
	var quoted = replaced(field, "\"", "\"\"")
	if crlf: quoted = replaced(replaced(quoted, "\r\n", "\n"), "\n", "\r\n")
	return f"\"{quoted}\""

// A sink that encodes each row as `stringify` does and puts the bytes into `output`.
type CsvRowsSink:
	output: WriteStream[Bytes]
	options: CsvOptions

fn var CsvRowsSink.write(move value: List[String]) Void!:
	text := stringify([value], self.options)?
	return self.output.write(text.to_bytes())

fn var CsvRowsSink.flush() Void!:
	return self.output.flush()

fn move CsvRowsSink.close() Void!:
	return self.output.close()

/*
Writes rows to a byte stream, each as `stringify` encodes it (quoting cells that need it, ending with the
options' line ending). Invalid `options` fail the first write with `EINVAL`. Writes delegate to `output`'s sink, which may wait.
`flush().wait()` uses that sink's completion condition; a pipe may retain up to its capacity of unread values. Closing the result closes `output`.
*/
export fn csv_writer(
	move output: WriteStream[Bytes],
	options: CsvOptions = CsvOptions(),
) WriteStream[List[String]]:
	return WriteStream[List[String]](CsvRowsSink(output: output, options: options))
