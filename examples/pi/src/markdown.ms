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

export type Renderer:
	// The unfinished last line.
	pending: String
	in_fence: Bool

fn line_out(self_fence: Bool, line: String) String:
	trimmed := line.trim_start()
	if self_fence: return "{esc}[2m│ {line}{esc}[0m"
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
