// JSON documents as the conformance runner observes and compares them: building
// objects, rewriting strings and keys, and the line-by-line difference of two
// documents.
import JsonValue, StringifyOptions, parse, stringify from "@std/data/json.ms"

export fn object() JsonValue:
	return JsonValue.ObjectValue(Map[String, JsonValue]())

export fn text(value: String) JsonValue:
	return JsonValue.StringValue(value.clone())

export fn number(value: Int) JsonValue:
	return JsonValue.NumberValue(f"{value}")

export fn flag(value: Bool) JsonValue:
	return JsonValue.BoolValue(value)

export fn list_of(items: List[JsonValue]) JsonValue:
	return JsonValue.ArrayValue(items)

export fn strings_of(items: List[String]) JsonValue:
	var out = List[JsonValue]()
	for item in items:
		out.append(text(item))
	return list_of(out)

// `members` with `key` set to `value`, placed last when new.
export fn with(members: JsonValue, key: String, value: JsonValue) JsonValue:
	match members:
		ObjectValue(values):
			var next = values.clone()
			next.add(key, value)
			return JsonValue.ObjectValue(next)
		_: return members.clone()

// The compact encoding, which is how a document prints in a message.
export fn compact(value: JsonValue) String:
	return stringify(value).get_or("")

// The pretty encoding a recorded expectation file holds, with its final newline.
export fn pretty_line(value: JsonValue) String:
	return stringify(value, StringifyOptions(indent: 2)).get_or("") + "\n"

// `value` with every member named `key` removed, at any depth through objects and arrays.
export fn without_key(value: JsonValue, key: String) JsonValue:
	match value:
		ObjectValue(values):
			var next = Map[String, JsonValue]()

			for entry in values.entries():
				if entry.key == key: continue

				next.add(entry.key, without_key(entry.value, key))

			return JsonValue.ObjectValue(next)
		ArrayValue(items):
			var next = List[JsonValue]()
			for item in items:
				next.append(without_key(item, key))
			return JsonValue.ArrayValue(next)
		_: return value.clone()

// `value` with every string rewritten by `change`.
export fn map_strings(value: JsonValue, change: fn(String) String) JsonValue:
	match value:
		StringValue(content): return JsonValue.StringValue(change(content))
		ObjectValue(values):
			var next = Map[String, JsonValue]()
			for entry in values.entries():
				next.add(entry.key, map_strings(entry.value, change))
			return JsonValue.ObjectValue(next)
		ArrayValue(items):
			var next = List[JsonValue]()
			for item in items:
				next.append(map_strings(item, change))
			return JsonValue.ArrayValue(next)
		_: return value.clone()

// Key paths of a document, such as `tests[].status`, so a missing or extra field is a
// protocol break.
export fn shape(value: JsonValue, path: String, var out: List[String]) Void:
	match value:
		ObjectValue(values):
			for entry in values.entries():
				next := if path.is_empty(): entry.key.clone() else: f"{path}.{entry.key}"
				if not out.contains(next): out.append(next.clone())
				shape(entry.value, next, out)
		ArrayValue(items):
			for item in items:
				shape(item, f"{path}[]", out)
		_: return

fn flatten(value: JsonValue, path: String, var out: List[String]) Void:
	match value:
		ObjectValue(values):
			for entry in values.entries():
				next := if path.is_empty(): entry.key.clone() else: f"{path}.{entry.key}"
				flatten(entry.value, next, out)
		ArrayValue(items):
			if items.is_empty(): out.append(f"{path}: []")
			for at in 0..items.length():
				flatten(items[at], f"{path}[{at}]", out)
		StringValue(content):
			if content.contains("\n"):
				var line_number = 1

				for line in content.split("\n"):
					out.append(f"{path}:{line_number}| {line}")
					line_number += 1
			else:
				out.append(f"{path}: {compact(value)}")
		_: out.append(f"{path}: {compact(value)}")

// The lines of `lines` with no counterpart in `other`; a line pairs with one
// occurrence.
fn unmatched(lines: List[String], other: List[String]) List[String]:
	var spare = Map[String, Int]()
	for line in other:
		spare.update(line.clone(), 0, fn n: n + 1)

	var out = List[String]()

	for line in lines:
		left := spare.get_or(line, 0)

		if left > 0:
			spare.add(line.clone(), left - 1)
		else:
			out.append(line.clone())

	return out

fn show(label: String, lines: List[String], max_lines: Int) String:
	var out = ""
	var shown = 0

	for line in lines:
		if shown >= max_lines: break

		out += f"{label} {line.chars().take(200).join("")}\n"
		shown += 1

	if lines.length() > max_lines:
		out += f"{label} ... {lines.length() - max_lines} more\n"
	return out

// How `actual` differs from `expected`, with equal leading and trailing lines left out
// and at most `max_lines` lines shown per side; `none` when they are equal.
export fn diff(expected: JsonValue, actual: JsonValue, max_lines: Int) String?:
	if expected == actual: return none

	var a = List[String]()
	var b = List[String]()
	flatten(expected, "", a)
	flatten(actual, "", b)

	var prefix = 0
	while prefix < a.length() and prefix < b.length() and a[prefix] == b[prefix]:
		prefix += 1

	var suffix = 0
	while (
		prefix + suffix < a.length()
		and prefix + suffix < b.length()
		and a[a.length() - 1 - suffix] == b[b.length() - 1 - suffix]
	):
		suffix += 1

	left := a.slice(prefix, a.length() - suffix).get_or([])
	right := b.slice(prefix, b.length() - suffix).get_or([])
	return (
		show("-", unmatched(left, right), max_lines)
		+ show("+", unmatched(right, left), max_lines)
	)

export fn parse_text(source: String) Result[JsonValue, String]:
	return parse(source).map_error(fn e: e.message)

// The string member `key` of `value`, or empty.
export fn string_member(value: JsonValue, key: String) String:
	if member := value.get(key): return member.as_string().get_or("")
	return ""

// The boolean member `key` of `value`, or false.
export fn bool_member(value: JsonValue, key: String) Bool:
	if member := value.get(key): return member.as_bool().get_or(false)
	return false
