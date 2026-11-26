// Rewrites Manuscript source from the old text syntax, where every "..." interpolated,
// to the current one, where only f"..." does. Usage: ms run tools/f-strings.ms --
// [--fences] files...
//
// For each file named on the command line (a `.ms` source, or a `.md` page whose
// manuscript fences are rewritten), a "..." or """ literal that holds an unescaped
// {expression} gets an
// `f` prefix, and one that holds none has its \{ and \} escapes replaced by plain braces. Raw
// text, comments and text that is already f"..." are left as they are, and so are the
// examples in documentation comments, unless the fences are converted too (they are, by
// default). Run it once per file: old-syntax and new-syntax text cannot be told apart,
// so a converted file that holds a plain "{..}" would be rewritten again. A file that
// already contains an f"..." literal is therefore skipped. `--fences` converts only the
// examples in documentation comments and Markdown fences, for files whose code is
// already converted. It prints the files it changed.
import (
	Bytes from "@std/bytes.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file, write_file from "@std/os/fs.ms",
)

fn is_name_byte(b Int) Bool {
	return (
		(b >= 48 and b <= 57)
		or (b >= 65 and b <= 90)
		or (b >= 97 and b <= 122)
		or b == 95
	)
}

type Scan {
	text String
	bytes Bytes
	at Int
	// Set when the source already holds an f"..." literal.
	saw_f Bool
}

fn Scan.byte(offset Int) Int {
	if offset < 0 or offset >= self.bytes.length() { return 0 }
	return self.bytes[offset].to_int()
}

// The source text from `start` up to `end`.
fn Scan.part(start, end Int) String {
	return self.text.slice(start, end)
}

fn Scan.starts(prefix String) Bool {
	return self.starts_at(self.at, prefix)
}

fn Scan.starts_at(offset Int, prefix String) Bool {
	bytes := prefix.view_bytes()
	for i in 0..bytes.length() {
		if self.byte(offset + i) != bytes[i].to_int() { return false }
	}
	return true
}

// The offset after the escape's character, which may be a multi-byte scalar.
fn Scan.past_escaped(offset Int) Int {
	var i = offset + 2
	while i < self.bytes.length() and self.byte(
		i
	) >= 128 and self.byte(i) < 192 { i += 1 }
	return i
}

fn Scan.after_name_byte() Bool {
	return self.at > 0 and is_name_byte(self.byte(self.at - 1))
}

// The index just after the next `needle` at or after the cursor, or the end of the
// text.
fn Scan.past(needle String) Int {
	found := self.part(self.at, self.text.length()).index_of(needle)
	if found != null { return self.at + found + needle.length() }

	return self.text.length()
}

// Whether the literal body starting at the cursor holds an unescaped `{` before its
// closing quote.
fn Scan.interpolates(multiline Bool) Bool {
	var i = self.at
	n := self.text.length()

	while i < n {
		c := self.byte(i)

		if c == 92 {
			if self.byte(i + 1) == 117 and self.byte(i + 2) == 123 {
				i = (self.part(i, n).index_of("}") or n - i) + i + 1
			} else {
				i = self.past_escaped(i)
			}

			continue
		}

		if c == 123 { return true }
		if c == 34 and (not multiline or self.starts_at(i, "\"\"\"")) { return false }
		if c == 10 and not multiline { return false }

		i += 1
	}

	return false
}

// Rewrites the literal whose opening quote is at the cursor, or copies it if
// unterminated.
// `written_f` is set when the source already has the `f` prefix, so the literal interpolates.
fn var Scan.literal(written_f Bool) String {
	n := self.text.length()
	multiline := self.starts("\"\"\"")
	quote := if multiline { "\"\"\"" } else { "\"" }
	first := self.at
	self.at += quote.length()

	formatted := written_f or self.interpolates(multiline)
	var out = ""
	var run = self.at

	while self.at < n {
		c := self.byte(self.at)

		if self.starts(quote) {
			out += self.part(run, self.at)
			self.at += quote.length()
			return (
				(if formatted and not written_f { "f" } else { "" })
				+ quote
				+ out
				+ quote
			)
		}

		if c == 10 and not multiline { break }

		if c == 92 {
			if self.byte(self.at + 1) == 117 and self.byte(self.at + 2) == 123 {
				self.at = self.past("}")
			} else if (
				not formatted
				and (
					self.byte(self.at + 1) == 123
					or self.byte(self.at + 1) == 125
				)
			) {
				out += self.part(run, self.at)
				run = self.at + 1
				self.at += 2
			} else {
				self.at = self.past_escaped(self.at)
			}

			continue
		}

		if formatted and c == 123 {
			out += self.part(run, self.at + 1)
			self.at += 1
			out += self.code(true)
			run = self.at
			continue
		}

		self.at += 1
	}

	// Unterminated: keep the source as written.
	return self.part(first, self.at)
}

// Rewrites code until the end of the text, or until the `}` that closes an
// interpolation.
fn var Scan.code(stop_at_brace Bool) String {
	n := self.text.length()
	var out = ""
	var run = self.at
	var depth = 0

	while self.at < n {
		c := self.byte(self.at)

		if self.starts("//") {
			self.at = (self.part(self.at, n).index_of("\n") or n - self.at) + self.at
		} else if self.starts("/*") {
			self.at = self.past("*/")
		} else if c == 114 and not self.after_name_byte() and self.starts("r\"\"\"") {
			self.at += 4
			self.at = self.past("\"\"\"")
		} else if c == 114 and not self.after_name_byte() and self.starts("r\"") {
			self.at += 2
			self.at = self.past("\"")
		} else if (
			c == 34
			or (
				c == 102
				and not self.after_name_byte()
				and self.byte(self.at + 1) == 34
			)
		) {
			written_f := c == 102
			if written_f { self.saw_f = true }
			out += self.part(run, self.at)

			if written_f {
				out += "f"
				self.at += 1
			}

			out += self.literal(written_f)
			run = self.at
		} else {
			if stop_at_brace and c == 125 {
				if depth == 0 {
					out += self.part(run, self.at)
					self.at += 1
					return out + "}"
				}

				depth -= 1
			}

			if stop_at_brace and c == 123 { depth += 1 }
			self.at += 1
		}
	}

	return out + self.part(run, n)
}

// The rewritten source, or none when it already holds an f"..." literal (it is
// converted).
fn convert(source String) String? {
	var scan = Scan(text: source.clone(), bytes: source.to_bytes(), at: 0, saw_f: false)
	converted := scan.code(false)
	if scan.saw_f { return null }

	return converted
}

// Rewrites the manuscript fences of a Markdown page, or of the documentation comments
// of a source file (`//` lines and `/* */` blocks carry fences too).
fn convert_fences(source String) String {
	var out = List[String]()
	var block = List[String]()
	var originals = List[String]()
	var fence = ""
	var prefix = ""

	for line in source.split("\n") {
		trimmed := line.trim_start()

		// The text after a `// ` comment marker, or the whole line.
		var body = trimmed.clone()

		if trimmed.starts_with("//") {
			body = trimmed.slice(2, trimmed.length())
			if body.starts_with(" ") {
				body = body.slice(1, body.length())
			}
		}

		lead := line.slice(0, line.length() - body.length())

		if fence == "" {
			out.append(line.clone())

			if body.starts_with("```manuscript") or body.starts_with("```ms") {
				fence = "```"
				prefix = lead.clone()
			}

			continue
		}

		if body.trim() == "```" and lead == prefix {
			if not block.is_empty() {
				converted := (convert(block.join("\n")) or block.join("\n")).split(
					"\n"
				).collect()

				for i in 0..converted.length() {
					if block[i] == "" {
						out.append(originals[i].clone())
					} else {
						out.append(prefix + converted[i])
					}
				}
			}

			block = List[String]()
			originals = List[String]()
			out.append(line.clone())
			fence = ""
			continue
		}

		originals.append(line.clone())

		if line.starts_with(prefix) {
			block.append(line.slice(prefix.length(), line.length()).clone())
		} else {
			block.append("")
		}
	}

	return out.join("\n")
}

fn main() Int {
	var fences_only = false

	for path in arguments() {
		if path == "--fences" {
			fences_only = true
			continue
		}

		source := read_file(path).wait().get().decode_utf8() or ""
		var converted = source.clone()

		if fences_only or path.ends_with(".md") {
			converted = convert_fences(source)
		} else {
			code := convert(source)
			if code != null { converted = convert_fences(code) }
		}

		if converted == source { continue }

		void write_file(path, converted, replace: true).wait().get()
		void stdout().write(f"{path}\n").get()
	}

	return 0
}
