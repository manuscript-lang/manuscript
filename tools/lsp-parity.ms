// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.process.run

// Language-server diagnostics parity (`ctest -R lsp_parity`): the editor must show the
// mistakes `ms check` prints. Opens a deterministic sample of the conformance fixtures
// through `ms lsp` and fails when
//   - a diagnostic of `ms check --json` has no diagnostic of the server at the same line and column, or
//   - the server reports a place `ms check` does not, although `ms check` stopped at no syntax or import error
//     (the server keeps checking past those, so it may report more after them).
// MS names the ms to run. Usage: ms run tools/lsp-parity.ms [-- every-nth-file]
import (
	Bytes from "@std/bytes.ms",
	parse, stringify from "@std/data/json.ms",
	arguments, working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// One in this many fixtures is compared.
fn every() Int {
	named := arguments()
	if named.is_empty() { return 40 }

	return named[0].parse_int() or 40
}

// The `file` URI of an absolute path: a drive path such as `D:/dir` takes the slash
// that makes it a URI path.
fn file_uri(path String) String {
	if path.starts_with("/") { return f"file://{path}" }
	return f"file:///{path}"
}

fn frame(body String) String {
	return f"Content-Length: {body.to_bytes().length()}\r\n\r\n{body}"
}

fn is_plain(text String) Bool {
	bytes := text.to_bytes()
	for index in 0..bytes.length() {
		if bytes.get(
			index
		) >= 128 or bytes.get(index) == 13 { return false }
	}
	return true
}

// The `line:column` places (by offset) of the diagnostics of `ms check --json`, and
// whether it stopped at a syntax or import error.
type Reference {
	places List[String]
	early Bool
}

// The one-based `line:column` of byte `offset` of `text`, counting a tab as one column
// as the server does.
fn place_of(text String, offset Int) String {
	bytes := text.to_bytes()
	var line = 1
	var column = 1

	for index in 0..offset {
		if index >= bytes.length() { break }

		if bytes.get(index) == 10 {
			line += 1
			column = 1
		} else {
			column += 1
		}
	}

	return f"{line}:{column}"
}

fn reference_of(ms, path, source String) Reference {
	var found = Reference(places: List[String](), early: false)
	finished := run(
		ms,
		["check", path.clone(), "--json"],
		RunOptions(timeout: seconds(60)),
	).wait()
	if not finished.is_ok() { return found }

	text := finished.get().stdout.decode_utf8() or ""
	doc := parse(text)
	if not doc.is_ok() { return found }

	list := doc.get().get("diagnostics")
	if list == null { return found }

	for item in list.as_list() or [] {
		where := item.get("position")
		code := item.get("code")
		if where == null or code == null { continue }

		offset := where.get("offset")
		named := where.get("file")
		if offset == null or named == null { continue }

		// `ms check` of a project reports the other files too; only this file's problems are compared.
		if not path.ends_with(
			f"/{named.as_string() or ""}"
		) { continue }

		found.places.append(place_of(source.clone(), offset.as_int() or 0))

		kind := code.as_string() or ""
		if kind.starts_with(
			"MS1"
		) or kind.starts_with("MS2") { found.early = true }
	}

	return found
}

// The diagnostics the server published for each document, as `line:column` places
// (one-based), by uri.
fn published_by(output Bytes) Map[String, List[String]] {
	var found = Map[String, List[String]]()
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

		parsed := parse(body)
		if not parsed.is_ok() { continue }

		doc := parsed.get()
		method := doc.get("method")
		if (
			method == null
			or (
				method.as_string()
				or ""
			) != "textDocument/publishDiagnostics"
		) { continue }

		params := doc.get("params")
		if params == null { continue }

		uri := params.get("uri")
		list := params.get("diagnostics")
		if uri == null or list == null { continue }

		var places = List[String]()

		for item in list.as_list() or [] {
			source := item.get("source")
			if source == null or (source.as_string() or "") != "manuscript" { continue }

			start := item.get_in(["range", "start"])
			if start == null { continue }

			line := start.get("line")
			character := start.get("character")
			if line == null or character == null { continue }

			places.append(f"{(line.as_int() or 0) + 1}:{(character.as_int() or 0) + 1}")
		}

		name := uri.as_string() or ""
		if found.get(name) == null { found.add(name.clone(), places) }
	}

	return found
}

fn main() Int {
	root := working_directory().get().clone()
	ms := tool_ms(root.clone())
	var files = List[String]()
	for dir in ["lang", "diagnostics", "format"] {
		for found in glob(f"{root}/tests/{dir}", GlobOptions(patterns: ["**/*.ms"])).get_or(
			[]
		) {
			files.append(f"{dir}/{found.path}")
		}
	}

	var paths = List[String]()

	for file in files {
		path := file.clone()
		if path.contains(
			"/projects/"
		) or path.contains("-fmt.ms") { continue }

		paths.append(f"{root}/tests/{path}")
	}

	paths.sort()

	var chosen = List[String]()
	var texts = List[String]()
	var index = 0

	while index < paths.length() {
		text := (read_file(paths[index]).wait().get().decode_utf8() or "").clone()

		if is_plain(text.clone()) {
			chosen.append(paths[index].clone())
			texts.append(text)
		}

		index += every()
	}

	var parts = List[String]()
	parts.append(
		frame(
			"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\""
			+ file_uri(root.clone())
			+ "\",\"capabilities\":{}}}"
		)
	)

	for at in 0..chosen.length() {
		encoded := stringify(texts[at].clone())
		quoted := if encoded.is_ok() { encoded.get().clone() } else { "\"\"" }
		parts.append(
			frame(
				"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\""
				+ file_uri(chosen[at].clone())
				+ "\",\"languageId\":\"manuscript\",\"version\":1,\"text\":"
				+ quoted
				+ "}}}"
			)
		)
		parts.append(
			frame(
				"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\""
				+ file_uri(chosen[at].clone())
				+ "\"}}}"
			)
		)
	}

	finished := run(
		ms,
		["lsp"],
		RunOptions(input: parts.join("").to_bytes(), timeout: seconds(600)),
	).wait()

	if not finished.is_ok() {
		print("lsp-parity: ms lsp did not run")
		return 1
	}

	published := published_by(finished.get().stdout)
	var failed = 0

	for at in 0..chosen.length() {
		expected := reference_of(ms.clone(), chosen[at].clone(), texts[at].clone())
		got := published.get(file_uri(chosen[at].clone()))

		if got == null {
			failed += 1
			print(f"NO REPLY {chosen[at]}")
			continue
		}

		for place in expected.places {
			if not got.contains(place) {
				failed += 1
				print(f"MISSING {chosen[at]}:{place}")
			}
		}

		if not expected.early {
			for place in got {
				if not expected.places.contains(place) {
					failed += 1
					print(f"EXTRA {chosen[at]}:{place}")
				}
			}
		}
	}

	print(f"lsp-parity: {chosen.length()} files, {failed} differences")
	if failed > 0 { return 1 }

	return 0
}
