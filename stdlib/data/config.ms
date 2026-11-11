// Builds the error for a malformed line: `config: line <n>: <reason>`, with the line in
// `details`.
fn config_error(line: Int, reason: String) Error:
	return Error(
		"config: line {line}: {reason}", kind: "EBADMSG", details: {"line": "{line}"}
	)

/*
Parses `.env` text into a map in file order, without touching the process environment.
Use it to layer settings: read the file, then let real variables win, `values.add(name, value)`.
To load a file straight into the environment use `load_environment` from `@std/os/process.ms`, which accepts the same syntax.

- Blank lines and `#` comment lines are skipped; a leading byte-order mark is ignored.
- `export NAME=value` is accepted, and a name is letters, digits and `_`, not starting with a digit.
- A bare value ends at an inline ` # comment` (a `#` after a space or tab, or first) and is trimmed, so `a#b` is the value `a#b`. A single-, double- or backtick-quoted value is literal, may span lines, and keeps any `#`.
- Only text after a closing quote may be a comment. A later duplicate name replaces the earlier value and keeps its first position.

Example: `parse_dotenv("PORT=8080\nNAME='my app' # label")` holds `PORT` as `"8080"` and `NAME` as `"my app"`.
*/
export fn parse_dotenv(text: String) Map[String, String]!:
	var out = Map[String, String]()

	// Split on LF alone: a CR before it stays until the parser knows it is outside a
	// quoted value.
	lines := text.cut_prefix("\u{feff}").get(text).split("\n")
	var index = 0

	while index < lines.length():
		number := index + 1

		// Text inside an opening quote is literal, so only the front of the line is
		// trimmed here.
		entry := lines[index].trim_start()
		index += 1
		if entry.trim().is_empty() or entry.starts_with("#"): continue

		assignment := entry.cut_prefix("export ").get(entry)
		found := assignment.index_of("=")
		if found.is_none(): return error(config_error(number, "expected NAME=value"))

		at := found.get(0)
		name := assignment.take(at).trim()
		if not valid_name(name): return error(
			config_error(number, "invalid variable name")
		)

		value := assignment.drop(at + 1).trim_start()
		quote := value.take(1)

		if quote != "'" and quote != "\"" and quote != "`":
			out.add(name, bare_value(value.trim()))
			continue

		// Only the newest line is searched for the closing quote, so a long value stays
		// linear.
		var parts = [value.drop(1)]
		var closing = parts[0].index_of(quote)

		while closing.is_none():
			if index >= lines.length(): return error(
				config_error(number, "unterminated quote")
			)

			parts.append(lines[index].clone())
			closing = lines[index].index_of(quote)
			index += 1

		last := parts.length() - 1
		body := parts.join("\n")
		end := body.scalar_length() - parts[last].scalar_length() + closing.get(0)
		trailing := body.drop(end + 1).trim()
		if not trailing.is_empty() and not trailing.starts_with("#"): return error(
			config_error(number, "unexpected text after quoted value")
		)

		out.add(name, body.take(end))

	return ok(out)

/*
Parses INI text into sections of settings, both in file order. Keys before the first `[section]` header go in the section named `""`.

- `[name]` starts a section; a repeated header continues the earlier one. Names and keys are trimmed.
- `key = value` and `key: value` both assign; the first `=` or `:` splits, so values may contain the other.
- Lines starting with `#` or `;` are comments, and so is text after ` #` or ` ;` in a value. A value wrapped in matching `"` or `'` keeps such text and loses the quotes.
- A later duplicate key in a section replaces the earlier value. A line without `=` or `:` returns EBADMSG.

Example: `parse_ini("[db]\nhost = localhost\nport: 5432")` holds `ini["db"]["port"]` as `"5432"`.
*/
export fn parse_ini(text: String) Map[String, Map[String, String]]!:
	var sections = Map[String, Map[String, String]]()
	sections.add("", Map[String, String]())

	var current = ""
	var number = 0

	for raw in text.cut_prefix("\u{feff}").get(text).lines():
		number += 1

		entry := raw.trim()
		if entry.is_empty() or entry.starts_with("#") or entry.starts_with(";"): continue

		if entry.starts_with("["):
			if not entry.ends_with("]"): return error(
				config_error(number, "unterminated section header")
			)

			current = entry.drop(1).take(entry.length() - 2).trim()
			sections.add_default(current.clone(), Map[String, String]())
			continue

		split := first_assignment(entry)
		if split.is_none(): return error(config_error(number, "expected key = value"))

		at := split.get(0)
		key := entry.take(at).trim()
		if key.is_empty(): return error(config_error(number, "empty key"))

		if var section = sections.get(current):
			section.add(key, ini_value(entry.drop(at + 1)))

	return ok(sections)

// The text before an inline comment: a `#` at the start or after a space or tab. Other
// `#` characters belong to the value.
fn bare_value(value: String) String:
	chars := value.chars()
	var previous = " "

	for index in 0..chars.length():
		if chars[index] == "#" and (previous == " " or previous == "\t"):
			return value.take(index).trim()

		previous = chars[index].clone()

	return value.trim()

fn valid_name(name: String) Bool:
	if name.is_empty(): return false

	var position = 0

	for code in name.scalar_values():
		letter := (code >= 97 and code <= 122) or (code >= 65 and code <= 90)
		digit := code >= 48 and code <= 57
		if not (letter or code == 95 or (digit and position > 0)): return false

		position += 1

	return true

fn first_assignment(entry: String) Int?:
	eq := entry.index_of("=")
	colon := entry.index_of(":")
	if eq.is_none(): return colon
	if colon.is_none(): return eq

	return eq.get(0).min(colon.get(0))

fn ini_value(value: String) String:
	trimmed := value.trim()
	quote := trimmed.take(1)
	quoted := quote == "\"" or quote == "'"

	// A closing quote followed only by whitespace and a ` #` or ` ;` comment ends the
	// value; the comment may itself contain or end with the quote, so this precedes the
	// whole-suffix rule.
	if quoted:
		if closing := trimmed.drop(1).index_of(quote):
			tail := trimmed.drop(closing + 2)
			for marker in [" #", " ;"]:
				if at := tail.index_of(marker):
					if tail.take(at).trim().is_empty(): return (
						trimmed
						.drop(1)
						.take(closing)
					)

	if trimmed.length() >= 2 and quoted and trimmed.ends_with(quote):
		return trimmed.drop(1).take(trimmed.length() - 2)

	var cut = value.length()
	for marker in [" #", " ;"]:
		if at := value.index_of(marker):
			cut = cut.min(at)
	return value.take(cut).trim()
