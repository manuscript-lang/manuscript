// The C parser's tables, read through `extern fn` (compiler/include/ms/tool.h is the
// other half of this contract). A tool links `libmstool.a`:
// `ms run tool.ms --link libmstool.a`.

// One token: the kind index into `token_kinds()`, the byte range in the CRLF-normalised
// text, and start and end positions in original-source coordinates.
export type Token:
	kind: Int
	lo: Int
	hi: Int
	offset: Int
	line: Int
	column: Int
	end_offset: Int
	end_line: Int
	end_column: Int

export enum LexError:
	Failed(code: Int, message: String)

extern fn ms_tool_lex(text: String) List[Int]!LexError

extern fn ms_tool_token_kinds() List[String]

fn token_width() Int: 9

// The token kind names, such as "NAME", "STRING", "(" and "fn", indexed by
// `Token.kind`.
export fn token_kinds() List[String]:
	return ms_tool_token_kinds()

// The index of the kind named `name`, or -1.
export fn token_kind(name: String) Int:
	kinds := ms_tool_token_kinds()
	for i in 0..kinds.length():
		if kinds[i] == name: return i
	return -1

// Lexes `text`; an error holds the first lexical error's message and byte offset.
export fn lex(text: String) List[Token]!LexError:
	flat := ms_tool_lex(text)?
	width := token_width()
	var tokens = List[Token]()
	var at = 0

	while at < flat.length():
		tokens.append(
			Token(
				kind: flat[at],
				lo: flat[at + 1],
				hi: flat[at + 2],
				offset: flat[at + 3],
				line: flat[at + 4],
				column: flat[at + 5],
				end_offset: flat[at + 6],
				end_line: flat[at + 7],
				end_column: flat[at + 8],
			)
		)
		at += width

	return ok(tokens)
