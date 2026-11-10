// Streaming markdown to ANSI: headings, bold, italics, inline code, fenced code, lists and quotes.
// Text arrives in arbitrary pieces; whole lines are rendered as they complete and `finish` flushes the rest.
esc := "\u{1b}"

type Style:
	bold: Bool
	italic: Bool
	code: Bool

// Renders inline spans of one line.
fn inline(text: String) String:
	var out = ""
	var bold = false
	var italic = false
	var code = false
	chars := text.chars()
	var i = 0

	while i < chars.length():
		c := chars[i]
		next := chars.get(i + 1, "")

		if c == "`":
			code = not code
			out = "{out}{if code: "{esc}[36m" else: "{esc}[39m"}"
			i += 1
			continue

		if code:
			out = "{out}{c}"
			i += 1
			continue

		if c == "*" and next == "*":
			bold = not bold
			out = "{out}{if bold: "{esc}[1m" else: "{esc}[22m"}"
			i += 2
			continue

		if c == "*" or c == "_" and (i == 0 or chars.get(i - 1, " ") == " "):
			italic = not italic
			out = "{out}{if italic: "{esc}[3m" else: "{esc}[23m"}"
			i += 1
			continue

		out = "{out}{c}"
		i += 1

	return "{out}{esc}[0m"

keywords := [
	"fn", "let", "const", "var", "if", "else", "for", "while", "return", "import",
	"export", "type", "class", "def", "function", "async", "await", "match", "enum",
	"impl", "struct", "pub", "use", "from", "in", "and", "or", "not", "true", "false",
	"none", "null", "break", "continue", "try"
]

fn is_word_char(c: String) Bool:
	return (
		c == "_"
		or (c >= "a" and c <= "z")
		or (c >= "A" and c <= "Z")
		or (c >= "0" and c <= "9")
	)

// Colors comments, strings, numbers and keywords in one line of code.
export fn highlight(line: String) String:
	chars := line.chars()
	var out = ""
	var i = 0

	while i < chars.length():
		c := chars[i]
		next := chars.get(i + 1, "")

		if (c == "/" and next == "/") or c == "#":
			out = "{out}{esc}[90m{chars.drop(i).join("")}{esc}[0m"
			break

		if c == "\"" or c == "'" or c == "`":
			var j = i + 1

			while j < chars.length() and chars[j] != c:
				if chars[j] == "\\": j += 1
				j += 1

			stop := if j < chars.length(): j + 1 else: chars.length()
			out = "{out}{esc}[32m{chars.slice(i, stop).get([]).join("")}{esc}[0m"
			i = stop
			continue

		if c >= "0" and c <= "9":
			var j = i
			while j < chars.length() and (is_word_char(chars[j]) or chars[j] == "."): j += 1
			out = "{out}{esc}[33m{chars.slice(i, j).get([]).join("")}{esc}[0m"
			i = j
			continue

		if is_word_char(c):
			var j = i
			while j < chars.length() and is_word_char(chars[j]): j += 1

			word := chars.slice(i, j).get([]).join("")
			out = "{out}{if keywords.contains(word): "{esc}[35m{word}{esc}[0m" else: word}"
			i = j
			continue

		out = "{out}{c}"
		i += 1

	return out

export type Renderer:
	// The unfinished last line.
	pending: String
	in_fence: Bool

fn line_out(self_fence: Bool, line: String) String:
	trimmed := line.trim_start()
	if self_fence: return "{esc}[2m│{esc}[0m {highlight(line)}"
	if trimmed.starts_with("### "): return "{esc}[1m{esc}[36m{inline(trimmed.drop(4))}{esc}[0m"
	if trimmed.starts_with("## "): return "{esc}[1m{esc}[34m{inline(trimmed.drop(3))}{esc}[0m"
	if trimmed.starts_with("# "): return "{esc}[1m{esc}[4m{inline(trimmed.drop(2))}{esc}[0m"
	if trimmed.starts_with("> "): return "{esc}[2m▌ {inline(trimmed.drop(2))}{esc}[0m"

	if trimmed.starts_with("- ") or trimmed.starts_with("* "):
		indent := line.take(line.length() - trimmed.length())
		return "{indent}• {inline(trimmed.drop(2))}"

	return inline(line)

impl Renderer:
	// Takes streamed text and returns the ANSI text that is ready to print.
	var fn feed(text: String) String:
		self.pending = "{self.pending}{text}"

		parts := self.pending.split("\n")
		var out = ""
		var i = 0

		while i < parts.length() - 1:
			out = "{out}{self.render_line(parts[i])}\n"
			i += 1

		self.pending = parts[parts.length() - 1].clone()
		return out

	var fn render_line(line: String) String:
		if line.trim_start().starts_with("```"):
			self.in_fence = not self.in_fence

			label := line.trim_start().drop(3).trim()
			return if self.in_fence: "{esc}[2m┌─ {label}{esc}[0m" else: "{esc}[2m└─{esc}[0m"

		return line_out(self.in_fence, line)

	// Renders whatever is left of an unfinished last line.
	var fn finish() String:
		rest := self.pending.clone()
		self.pending = ""
		self.in_fence = false
		if rest.is_empty(): return ""

		return self.render_line(rest)

export fn new_renderer() Renderer:
	return Renderer(pending: "", in_fence: false)
