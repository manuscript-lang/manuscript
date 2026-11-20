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
		code.clone(),
		severity.clone(),
		message.clone(),
		file.clone(),
		offset,
		line,
		column,
	)
