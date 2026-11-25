// ms: allow_effect std.fs.read
// ms: allow_effect std.process.run

// Language-server sweep (`ctest -R lsp_sweep`): opens standard-library modules through
// `ms lsp`, asks for the definition and hover of every identifier in code, and fails when
//   - a definition lands on text that is not the identifier asked about (a jump to the wrong place), or
//   - more identifiers than the ceiling below have no hover (navigation stopped working in some construct).
// The modules cover the prelude, generics, borrowed signatures, extern declarations and
// grouped declarations. MS names the ms to run (default
// .artifacts/build/ci/src/cli/ms). Usage: ms run tools/lsp-sweep.ms
import (
	Bytes from "@std/bytes.ms",
	JsonValue, parse from "@std/data/json.ms",
	working_directory from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// Modules swept: the path below `src/stdlib` and the name the language server knows it
// by.
fn modules() List[String] {
	return [
		"bytes.ms", "collections/collections.ms", "core/core.ms", "core/string.ms",
		"os/path.ms", "io/io.ms"
	]
}

// Identifiers with no hover that the sweep tolerates: written primitive types, which
// have no declaration to describe, and names inside text interpolation. Lower this as
// navigation improves; raise it never.
fn ceiling_percent() Int {
	return 4
}

// Words that are not names: keywords, literals and the primitive types.
fn skipped() List[String] {
	return [
		"fn", "var", "let", "type", "enum", "interface", "opaque", "extern", "export",
		"import", "from", "return", "if", "else", "for", "in", "while", "match",
		"break", "continue", "defer", "move", "hold", "and", "or", "not", "true",
		"false", "null", "void", "test", "bench", "const", "as", "is", "self", "Self",
		"Int", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64",
		"Float", "Float32", "Bool", "String", "Void", "Never", "Bytes", "Error", "ok",
		"error", "some", "default", "ms", "std", "throws", "spawn", "try", "catch",
		"yield", "await", "async", "unsafe", "pub", "static", "impl", "where", "ref"
	]
}

// One word asked about: where it is, and what the server answered.
type Probe {
	module String
	line, column Int
	word String
}

fn is_word_byte(b UInt8) Bool {
	return (
		(b >= 97 and b <= 122)
		or (b >= 65 and b <= 90)
		or (b >= 48 and b <= 57)
		or b == 95
	)
}

// The identifiers written in code on each line, with comments and text literals
// skipped.
fn probes_of(module, text String) List[Probe] {
	skipped := skipped()
	var found = List[Probe]()
	var in_block = false
	var line_number = 0

	for line in text.split("\n") {
		line_number += 1

		bytes := line.to_bytes()
		count := bytes.length()
		var at = 0
		var ascii = true
		for i in 0..count {
			if bytes.get(
				i
			) >= 128 { ascii = false }
		}
		if not ascii { continue }

		while at < count {
			b := bytes.get(at)

			if in_block {
				if b == 42 and at + 1 < count and bytes.get(at + 1) == 47 {
					in_block = false
					at += 2
				} else {
					at += 1
				}
			} else if b == 47 and at + 1 < count and bytes.get(at + 1) == 47 {
				at = count
			} else if b == 47 and at + 1 < count and bytes.get(at + 1) == 42 {
				in_block = true
				at += 2
			} else if b == 34 {
				at += 1
				while at < count and bytes.get(at) != 34 {
					at += if bytes.get(at) == 92 { 2 } else { 1 }
				}
				at += 1
			} else if is_word_byte(b) and not (b >= 48 and b <= 57) {
				start := at
				while at < count and is_word_byte(bytes.get(at)) { at += 1 }

				word := line.slice(start, at)
				if not skipped.contains(word) {
					found.append(
						Probe(
							module: module.clone(),
							line: line_number - 1,
							column: start,
							word: word.clone(),
						)
					)
				}
			} else if is_word_byte(b) {
				while at < count and is_word_byte(bytes.get(at)) { at += 1 }
			} else {
				at += 1
			}
		}
	}

	return found
}

fn frame(body String) String {
	return f"Content-Length: {body.to_bytes().length()}\r\n\r\n{body}"
}

fn uri_of(module String) String {
	name := if module.starts_with("core/") {
		module.slice(5, module.length())
	} else {
		module.slice(0, module.length())
	}
	return f"manuscript-stdlib:///{name}"
}

fn request(id Int, method, uri String, probe Probe) String {
	where := (
		"{\"line\":"
		+ f"{probe.line}"
		+ ",\"character\":"
		+ f"{probe.column}"
		+ "}"
	)
	return frame(
		"{\"jsonrpc\":\"2.0\",\"id\":"
		+ f"{id}"
		+ ",\"method\":\"textDocument/"
		+ method
		+ "\",\"params\":{\"textDocument\":{\"uri\":\""
		+ uri
		+ "\"},\"position\":"
		+ where
		+ "}}"
	)
}

// The replies the server wrote, by request id.
fn replies_of(output Bytes) Map[Int, JsonValue] {
	var replies = Map[Int, JsonValue]()
	var at = 0
	total := output.length()
	marker := "\r\n\r\n".to_bytes()

	while at < total {
		rest := output.view(at, total)
		head_end := rest.index_of(marker)
		if head_end == null { break }

		head := rest.view(0, head_end).decode_utf8() or ""
		colon := head.index_of(":") or 0
		length := head.slice(colon + 1, head.length()).trim().parse_int() or 0
		body_start := at + head_end + 4
		body := output.view(body_start, body_start + length).decode_utf8() or ""
		at = body_start + length

		if doc := parse(body) {
			id := doc.get("id")

			if id != null {
				number := id.as_int()
				if number != null {
					replies.add(number, doc.clone())
				}
			}
		}
	}

	return replies
}

// The text of line `at` of the bundled module a `manuscript-stdlib:` URI names; the
// module is read once.
fn line_of(root, uri String, at Int, var sources Map[String, List[String]]) String {
	module := uri.replace("manuscript-stdlib:///", "")

	if sources.get(module) == null {
		var lines = List[String]()

		for path in [f"{root}/src/stdlib/{module}", f"{root}/src/stdlib/core/{module}"] {
			bytes := read_file(path).wait()

			if bytes.is_ok() {
				lines.extend((bytes.get().decode_utf8() or "").split("\n"))
				break
			}
		}

		sources.add(module.clone(), lines)
	}

	found := sources.get(module)
	if found == null or at >= found.length() { return "" }

	return found[at].clone()
}

fn main() Int {
	root := working_directory().get().clone()
	ms := tool_ms(root.clone())
	var sources = Map[String, List[String]]()
	var probes = List[Probe]()

	for module in modules() {
		text := (
			read_file(
				f"{root}/src/stdlib/{module}"
			).wait().get().decode_utf8()
			or ""
		).clone()
		lines := text.split("\n")
		sources.add(module.clone(), lines.clone())
		probes.extend(probes_of(module, text))
	}

	var parts = List[String]()
	parts.append(
		frame(
			"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://"
			+ root
			+ "\",\"capabilities\":{}}}"
		)
	)
	for module in modules() {
		parts.append(
			frame(
				"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\""
				+ uri_of(module)
				+ "\",\"languageId\":\"manuscript\",\"version\":1,\"text\":\"\"}}}"
			)
		)
	}

	var id = 1

	for probe in probes {
		id += 1
		parts.append(request(id, "definition", uri_of(probe.module), probe))
		id += 1
		parts.append(request(id, "hover", uri_of(probe.module), probe))
	}

	finished := run(
		ms,
		["lsp"],
		RunOptions(input: parts.join("").to_bytes(), timeout: seconds(600)),
	).wait()

	if not finished.is_ok() {
		print("lsp-sweep: ms lsp did not run")
		return 1
	}

	replies := replies_of(finished.get().stdout)
	var wrong = 0
	var missing = 0
	var asked = 0
	var shown = 0

	for index in 0..probes.length() {
		probe := probes[index]
		asked += 1

		jump := replies.get(2 + index * 2)
		hover := replies.get(3 + index * 2)

		if jump != null {
			targets := jump.get("result")

			if targets != null {
				for target in targets.as_list() or [] {
					start := target.get_in(["range", "start"])
					end := target.get_in(["range", "end"])
					uri := target.get("uri")
					if start == null or end == null or uri == null { continue }

					l := start.get("line")
					c := start.get("character")
					e := end.get("character")
					if l == null or c == null or e == null { continue }

					at_line := l.as_int() or 0
					from := c.as_int() or 0
					if at_line == 0 and from == 0 { continue }

					name := uri.as_string() or ""
					to := e.as_int() or 0
					text := line_of(root, name, at_line, sources)
					spelled := if from <= to and to <= text.length() {
						text.slice(from, to)
					} else {
						""
					}

					if spelled != probe.word {
						wrong += 1

						if shown < 20 {
							shown += 1
							print(
								f"WRONG {probe.module}:{probe.line + 1}:{probe.column + 1} {probe.word} jumps to {name}:{at_line + 1}:{from + 1}"
							)
						}
					}
				}
			}
		}

		var has_hover = false

		if hover != null {
			result := hover.get("result")
			if result != null { has_hover = not result.is_null() }
		}

		if not has_hover { missing += 1 }
	}

	percent := missing * 100 / (if asked == 0 { 1 } else { asked })
	print(
		f"lsp-sweep: {asked} identifiers, {wrong} wrong jumps, {missing} without hover ({percent}%, ceiling {ceiling_percent()}%)"
	)
	if wrong > 0 or percent > ceiling_percent() { return 1 }

	return 0
}
