// One advisory finding, as `ms lint` reports it. `offset`, `line` and `column` follow
// the original
// source: offset is a 0-based byte offset, line and column are 1-based and count bytes.
export type Finding:
	code: String
	severity: String
	message: String
	file: String
	offset: Int
	line: Int
	column: Int
	// A machine-applicable edit that resolves the finding, applied by `ms lint --fix`:
	// the byte range `fix_from..fix_to` becomes `fix_text`. `fix_from` is -1 when there
	// is none.
	fix_from: Int = -1
	fix_to: Int = -1
	fix_text: String = ""

export fn finding(
	code: String,
	severity: String,
	message: String,
	file: String,
	offset: Int,
	line: Int,
	column: Int,
) Finding:
	return Finding(
		code: code.clone(),
		severity: severity.clone(),
		message: message.clone(),
		file: file.clone(),
		offset: offset,
		line: line,
		column: column,
	)

// `found` with the edit that fixes it: bytes `from..to` of the source become `text`.
export fn with_fix(found: Finding, from: Int, to: Int, text: String) Finding:
	return Finding(
		code: found.code.clone(),
		severity: found.severity.clone(),
		message: found.message.clone(),
		file: found.file.clone(),
		offset: found.offset,
		line: found.line,
		column: found.column,
		fix_from: from,
		fix_to: to,
		fix_text: text.clone(),
	)
