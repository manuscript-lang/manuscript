// The language server session: one decoded message in, the messages to send out. It
// follows crates/ms-lsp/src/server.rs for the protocol rules: error codes, the
// initialize and shutdown order, and incremental document sync with UTF-16 positions.
// Diagnostics come from `ms check --json` (see check.ms) until the C checker feeds
// facts directly.
import (
	JsonValue, parse from "@std/data/json.ms",
	basename from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	Occurrence from "./index.ms",
	Renamed,
	highlights,
	plan_rename,
	prepare_rename,
	references,
	rename_edit from "./refs.ms",
	Field,
	error_message,
	field,
	int_at,
	json_text,
	list,
	notification,
	number,
	object,
	result_message,
	string_at from "./rpc.ms",
	document_symbols, folding_ranges from "./structure.ms",
	Position, offset_at, position_at, range_json, replace_range from "./text.ms",
	filename, is_file from "./uri.ms",
)

SERVER_NAME := "manuscript"

export type Document:
	text: String
	version: Int

// What a request or notification asks of the session loop after it was handled.
export enum Next:
	Continue
	// `exit` after `shutdown`, or the input ended: exit status 0.
	Stop
	// `exit` without `shutdown`: exit status 1.
	StopFailed

export type Outcome:
	// Messages to send, in order.
	messages: List[String] = []
	next: Next = Next.Continue

// What the server asks of the outside world, so tests can stand in for the checker and
// the formatter.
// What the checker found for a request: text to show and the byte range it covers.
export type Found:
	text: String
	start: Int
	end: Int

export type Backend:
	// The text and range to show for the byte offset in a buffer (path, text, offset).
	hover: fn(String, String, Int) Found?
	// Where the name at the byte offset is declared, in the same buffer.
	definition: fn(String, String, Int) Found?
	// Where every declared name of a buffer is declared and used (path, text); empty
	// when the buffer does not check.
	index: fn(String, String) List[Occurrence]
	// The diagnostics of one open document: file path and buffer text.
	check: fn(String, String) List[JsonValue]
	// The formatted text of a buffer, or why it cannot be formatted.
	format: fn(String, String) Result[String, Error]

export type Server:
	documents: Map[String, Document] = Map[String, Document]()
	// Open documents whose diagnostics must be sent again, in the order they changed.
	dirty: List[String] = []
	version: String = ""
	initialized: Bool = false
	shut_down: Bool = false

// The `start` or `end` position of a change's range.
fn range_end(change: JsonValue, which: String) Position:
	return Position(
		line: int_at(change, ["range", which.clone(), "line"], 0),
		character: int_at(change, ["range", which, "character"], 0),
	)

// The byte offset of the request's `position`.
fn request_offset(text: String, params: JsonValue) Int:
	return offset_at(
		text,
		Position(
			line: int_at(params, ["position", "line"], 0),
			character: int_at(params, ["position", "character"], 0),
		),
	)

fn capabilities(server: Server) JsonValue:
	return object(
		[
			field(
				"capabilities",
				object(
					[
						// Incremental sync, positions in UTF-16 units.
						field("textDocumentSync", number(2)),
						field(
							"positionEncoding",
							json_text("utf-16"),
						),
						field(
							"documentFormattingProvider",
							JsonValue.BoolValue(true),
						),
						field(
							"hoverProvider",
							JsonValue.BoolValue(true),
						),
						field(
							"definitionProvider",
							JsonValue.BoolValue(true),
						),
						field(
							"referencesProvider",
							JsonValue.BoolValue(true),
						),
						field(
							"documentHighlightProvider",
							JsonValue.BoolValue(true),
						),
						field(
							"renameProvider",
							object(
								[
									field(
										"prepareProvider",
										JsonValue.BoolValue(
											true
										),
									)
								]
							),
						),
					]
				),
			),
			field(
				"serverInfo",
				object(
					[
						field("name", json_text(SERVER_NAME)),
						field(
							"version",
							json_text(server.version),
						),
					]
				),
			),
		]
	)

// One edit that replaces the whole buffer with `formatted`.
fn whole_document_edit(source: String, formatted: String) JsonValue:
	end := position_at(source, source.length())
	return object(
		[
			field(
				"range",
				object(
					[
						field(
							"start",
							object(
								[
									field(
										"line",
										number(
											0
										),
									),
									field(
										"character",
										number(
											0
										),
									),
								]
							),
						),
						field(
							"end",
							object(
								[
									field(
										"line",
										number(
											end.line
										),
									),
									field(
										"character",
										number(
											end.character
										),
									),
								]
							),
						),
					]
				),
			),
			field("newText", json_text(formatted)),
		]
	)

fn var Server.mark_dirty(uri: String) Void:
	if not self.dirty.contains(uri): self.dirty.append(uri.clone())

// Applies the `contentChanges` of a `didChange`: each is a range edit or, without a
// range, the whole new text.
fn apply_changes(current: String, changes: List[JsonValue]) String:
	var result = current.clone()

	for change in changes:
		replacement := string_at(change, ["text"])

		if change.get("range").is_none():
			result = replacement
		else:
			result = replace_range(
				result,
				range_end(change, "start"),
				range_end(change, "end"),
				replacement,
			)

	return result

fn var Server.did_change(params: JsonValue) Void:
	uri := string_at(params, ["textDocument", "uri"])
	if uri.is_empty(): return

	existing := self.documents.get(uri).map(fn(found: Document) Document: found.clone())

	if current := existing:
		changes := params.get("contentChanges").get_or(list([])).as_list().get_or([])
		version := int_at(params, ["textDocument", "version"], current.version)
		self.documents.add(
			uri.clone(),
			Document(
				text: apply_changes(current.text, changes),
				version: version,
			),
		)
		self.mark_dirty(uri)

fn var Server.did_open(params: JsonValue) Void:
	uri := string_at(params, ["textDocument", "uri"])
	if uri.is_empty(): return

	self.documents.add(
		uri.clone(),
		Document(
			text: string_at(params, ["textDocument", "text"]),
			version: int_at(params, ["textDocument", "version"], 0),
		),
	)
	self.mark_dirty(uri)

fn var Server.did_close(params: JsonValue, var out: Outcome) Void:
	uri := string_at(params, ["textDocument", "uri"])
	if uri.is_empty(): return

	self.documents.remove(uri.clone())
	self.dirty.retain(fn(pending: String) Bool: pending != uri)
	out.messages.append(diagnostics_message(uri, []))

// A `publishDiagnostics` message.
export fn diagnostics_message(
	uri: String,
	diagnostics: List[JsonValue],
	version: Int? = none,
) String:
	var fields = [field("uri", json_text(uri)), field("diagnostics", list(diagnostics))]
	if known := version: fields.append(field("version", number(known)))
	return notification("textDocument/publishDiagnostics", object(fields))

// Handles one decoded message body.
fn var Server.handle(body: String, backend: Backend) Outcome:
	var out = Outcome()
	parsed := parse(body)

	if parsed.is_error():
		out.messages.append(error_message(JsonValue.Null, -32700, "invalid JSON"))
		return out

	message := parsed.get()
	var id: JsonValue? = none
	if found := message.get("id"): id = found.clone()

	method := string_at(message, ["method"])

	if (
		message.as_map().is_none()
		or string_at(message, ["jsonrpc"]) != "2.0"
		or method.is_empty()
	):
		out.messages.append(error_message(JsonValue.Null, -32600, "invalid request"))
		return out

	params := message.get("params").get_or(JsonValue.Null)

	if self.shut_down and method != "exit":
		if request_id := id: out.messages.append(
			error_message(request_id, -32600, "server has shut down")
		)
		return out

	if not self.initialized and method != "initialize" and method != "exit":
		if request_id := id: out.messages.append(
			error_message(request_id, -32002, "server not initialized")
		)
		return out

	// Edits batch up; anything else first sees the diagnostics of the edits before it.
	if not method.starts_with("textDocument/did") and method != "initialized":
		out.messages.extend(self.publish(backend))

	var result = JsonValue.Null
	var known = true
	var failure = ""

	if method == "initialize":
		self.initialized = true
		result = capabilities(self)
	else if method == "initialized": result = JsonValue.Null
	else if method == "shutdown": self.shut_down = true
	else if method == "exit":
		if self.shut_down: out.next = Next.Stop
		else: out.next = Next.StopFailed

		return out
	else if method == "textDocument/didOpen": self.did_open(params)
	else if method == "textDocument/didChange": self.did_change(params)
	else if method == "textDocument/didClose": self.did_close(params, out)
	else if method == "textDocument/didSave": result = JsonValue.Null
	else if method == "textDocument/documentSymbol":
		document := self.documents.get(string_at(params, ["textDocument", "uri"]))
		result = list([])
		if document.is_some(): result = list(document_symbols(document.get().text))
	else if method == "textDocument/foldingRange":
		document := self.documents.get(string_at(params, ["textDocument", "uri"]))
		result = JsonValue.Null
		if document.is_some(): result = list(folding_ranges(document.get().text))
	else if method == "textDocument/hover":
		uri := string_at(params, ["textDocument", "uri"])
		document := self.documents.get(uri)
		result = JsonValue.Null

		if document.is_some() and is_file(uri):
			text := document.get().text
			found := backend.hover(filename(uri), text, request_offset(text, params))
			if shown := found: result = object(
				[
					field(
						"contents",
						object(
							[
								field(
									"kind",
									json_text(
										"markdown"
									),
								),
								field(
									"value",
									json_text(
										f"```ms\n{shown.text}\n```"
									),
								),
							]
						),
					),
					field(
						"range",
						range_json(text, shown.start, shown.end),
					),
				]
			)
	else if method == "textDocument/definition":
		uri := string_at(params, ["textDocument", "uri"])
		document := self.documents.get(uri)
		result = JsonValue.Null

		if document.is_some() and is_file(uri):
			text := document.get().text
			found := backend.definition(
				filename(uri),
				text,
				request_offset(text, params),
			)
			if target := found: result = object(
				[
					field("uri", json_text(uri)),
					field(
						"range",
						range_json(
							text,
							target.start,
							target.end,
						),
					),
				]
			)
	else if (
		method == "textDocument/references"
		or method == "textDocument/documentHighlight"
	):
		uri := string_at(params, ["textDocument", "uri"])
		document := self.documents.get(uri)
		result = JsonValue.Null

		if document.is_some() and is_file(uri):
			text := document.get().text
			offset := request_offset(text, params)
			found := backend.index(filename(uri), text)
			include := params.get_in(["context", "includeDeclaration"]).map(
				fn(flag: JsonValue) Bool: flag.as_bool().get_or(false)
			).get_or(false)

			if method == "textDocument/references":
				result = references(uri, text, found, offset, include)
			else: result = highlights(text, found, offset)
	else if method == "textDocument/prepareRename" or method == "textDocument/rename":
		uri := string_at(params, ["textDocument", "uri"])
		document := self.documents.get(uri).map(
			fn(found: Document) Document: found.clone()
		)

		if document.is_none() or not is_file(uri): failure = "document is not open"
		else:
			text := document.get().text
			path := filename(uri)
			offset := request_offset(text, params)
			found := backend.index(path, text)
			name := string_at(params, ["newName"])

			if found.is_empty(): failure = "rename requires a checked document"
			else if method == "textDocument/prepareRename":
				prepared := prepare_rename(text, found, offset)

				if prepared.is_error(): failure = prepared.err().message
				else: result = prepared.get()
			else if name.is_empty(): failure = "new name is empty"
			else:
				plan := plan_rename(text, found, offset, name)
				failure = rename_failure(plan, backend, path, text)
				if failure.is_empty(): result = rename_edit(
					uri,
					document.get().version,
					text,
					plan.get(),
					name,
				)
	else if method == "textDocument/formatting":
		uri := string_at(params, ["textDocument", "uri"])
		document := self.documents.get(uri).map(
			fn(found: Document) Document: found.clone()
		)

		if document.is_none(): failure = "document is not open"
		else if is_file(uri):
			formatted := backend.format(filename(uri), document.get().text)

			if formatted.is_error(): failure = formatted.err().message
			else: result = list(
				[
					whole_document_edit(
						document.get().text,
						formatted.get(),
					)
				]
			)
		else: result = list([])
	else: known = false

	if request_id := id:
		if not failure.is_empty(): out.messages.append(
			error_message(request_id, -32602, failure)
		)
		else if known: out.messages.append(result_message(request_id, result))
		else: out.messages.append(
			error_message(request_id, -32601, "method not supported")
		)

	return out

// Why a planned rename is refused: the plan itself, a buffer that does not check now
// (the occurrences cannot be trusted), or edits that leave it not checking.
fn rename_failure(
	plan: Result[Renamed, Error],
	backend: Backend,
	path: String,
	text: String,
) String:
	if plan.is_error(): return plan.err().message

	before := backend.check(path, text)
	if not before.is_empty(): return f"rename requires a clean workspace: {basename(path)}"

	after := backend.check(path, plan.get().updated)
	if after.is_empty(): return ""

	reason := string_at(after[0], ["message"])
	return f"rename would break {basename(path)}: {reason}"

// The messages that bring the diagnostics of every changed open document up to date,
// using `check` to compute the diagnostics of one document.
fn var Server.publish(backend: Backend) List[String]:
	var messages: List[String] = []
	pending := self.dirty.clone()
	self.dirty = []

	for uri in pending:
		if document := self.documents.get(uri):
			var found: List[JsonValue] = []
			if is_file(uri): found = backend.check(filename(uri), document.text)
			messages.append(diagnostics_message(uri, found, document.version))

	return messages

fn no_diagnostics(path: String, source: String) List[JsonValue]: []

fn shout(path: String, source: String) Result[String, Error]:
	if source.contains("bad"): return error(Error("cannot parse"))
	return ok(source.upper())

fn no_index(path: String, source: String) List[Occurrence]: []

fn nothing_found(path: String, source: String, offset: Int) Found?: none

// A fixed answer: the first word of the buffer.
fn first_word(path: String, source: String, offset: Int) Found?:
	return Found(text: "word: String", start: 0, end: 5)

fn fake() Backend: Backend(
	index: no_index,
	check: no_diagnostics,
	format: shout,
	hover: first_word,
	definition: first_word,
)

fn initialized_server() Server:
	var server = Server(version: "0.0.0")
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
		fake(),
	)
	return server

test "requests before initialize are refused":
	var server = Server()
	out := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"textDocument/hover\"}",
		fake(),
	)
	expect_equal(
		out.messages,
		[
			"{\"jsonrpc\":\"2.0\",\"id\":7,\"error\":{\"code\":-32002,\"message\":\"server not initialized\"}}"
		],
	)?

test "initialize answers with the capabilities":
	var server = Server(version: "1.2.3")
	out := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
		fake(),
	)
	expect_equal(out.messages.length(), 1)?
	expect_equal(out.messages[0].contains("\"textDocumentSync\":2"), true)?
	expect_equal(out.messages[0].contains("\"version\":\"1.2.3\""), true)?

test "bad input gets the JSON-RPC errors":
	var server = initialized_server()
	expect_equal(server.handle("{", fake()).messages[0].contains("-32700"), true)?
	expect_equal(server.handle("[]", fake()).messages[0].contains("-32600"), true)?
	expect_equal(
		server.handle(
			"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"nope\"}",
			fake(),
		).messages[0].contains("-32601"),
		true,
	)?
	expect_equal(
		server.handle(
			"{\"jsonrpc\":\"2.0\",\"method\":\"nope\"}",
			fake(),
		).messages,
		[],
	)?

test "shutdown then exit stops cleanly, exit alone fails":
	var server = initialized_server()
	server.handle("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}", fake())

	out := server.handle("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", fake())
	expect_equal(out.next, Next.Stop)?

	var other = initialized_server()
	expect_equal(
		other.handle("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", fake()).next,
		Next.StopFailed,
	)?

test "incremental changes edit the open document":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"ab\\ncd\"}}}",
		fake(),
	)
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":2},\"contentChanges\":[{\"range\":{\"start\":{\"line\":0,\"character\":1},\"end\":{\"line\":1,\"character\":1}},\"text\":\"X\"}]}}",
		fake(),
	)
	expect_equal(server.documents.get("file:///a.ms").get().text, "aXd")?
	expect_equal(server.documents.get("file:///a.ms").get().version, 2)?

	messages := server.publish(fake())
	expect_equal(messages.length(), 1)?
	expect_equal(messages[0].contains("\"version\":2"), true)?

test "closing a document clears its diagnostics":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"x\"}}}",
		fake(),
	)

	out := server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"}}}",
		fake(),
	)
	expect_equal(out.messages.length(), 1)?
	expect_equal(out.messages[0].contains("\"diagnostics\":[]"), true)?
	expect_equal(server.publish(fake()), [])?

test "formatting replaces the whole buffer with the formatted text":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"ab\\ncd\"}}}",
		fake(),
	)

	out := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"}}}",
		fake(),
	)

	// The pending diagnostics go out first, then the answer.
	expect_equal(out.messages.length(), 2)?
	expect_equal(
		out.messages[1],
		"{\"jsonrpc\":\"2.0\",\"id\":5,\"result\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":2}},\"newText\":\"AB\\nCD\"}]}",
	)?

test "formatting a buffer that does not parse, or is not open, is an invalid-params error":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"bad\"}}}",
		fake(),
	)

	broken := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"}}}",
		fake(),
	)
	expect_equal(broken.messages[1].contains("\"code\":-32602"), true)?
	expect_equal(broken.messages[1].contains("cannot parse"), true)?

	closed := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///other.ms\"}}}",
		fake(),
	)
	expect_equal(closed.messages[0].contains("document is not open"), true)?

test "the outline and folds answer for open documents and are empty or null otherwise":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"fn main() Int:\\n\\treturn 1\\n\"}}}",
		fake(),
	)

	symbols := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"}}}",
		fake(),
	)
	expect_equal(symbols.messages[1].contains("\"name\":\"main\""), true)?

	folds := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"textDocument/foldingRange\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"}}}",
		fake(),
	)
	expect_equal(
		folds.messages[0],
		"{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":[{\"startLine\":0,\"endLine\":1,\"kind\":\"region\"}]}",
	)?

	closed := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"file:///none.ms\"}}}",
		fake(),
	)
	expect_equal(closed.messages[0], "{\"jsonrpc\":\"2.0\",\"id\":10,\"result\":[]}")?

	unknown := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"textDocument/foldingRange\",\"params\":{\"textDocument\":{\"uri\":\"file:///none.ms\"}}}",
		fake(),
	)
	expect_equal(unknown.messages[0], "{\"jsonrpc\":\"2.0\",\"id\":11,\"result\":null}")?

test "hover and definition answer with a range, and nothing for an unknown buffer":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"hello world\\n\"}}}",
		fake(),
	)

	hovered := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":0,\"character\":2}}}",
		fake(),
	)
	expect_equal(
		hovered.messages[hovered.messages.length() - 1].contains(
			"word: String"
		),
		true,
	)?
	expect_equal(
		hovered.messages[hovered.messages.length() - 1].contains(
			"\"character\":5"
		),
		true,
	)?

	defined := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":0,\"character\":2}}}",
		fake(),
	)
	expect_equal(defined.messages[0].contains("file:///a.ms"), true)?

	unknown := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///none.ms\"},\"position\":{\"line\":0,\"character\":0}}}",
		fake(),
	)
	expect_equal(unknown.messages[0].contains("\"result\":null"), true)?

// The occurrences of `x := 1\nreturn x`, written as the real index would.
fn two_uses(path: String, source: String) List[Occurrence]:
	return [
		Occurrence(key: "b:0", name: "x", start: 0, end: 1, declaration: true),
		Occurrence(
			key: "b:0",
			name: "x",
			start: 14,
			end: 15,
			declaration: false,
		),
	]

fn broken_after(path: String, source: String) List[JsonValue]:
	if source.starts_with("y"): return [
		object([field("message", json_text("unknown name"))])
	]
	return []

fn indexed() Backend: Backend(
	index: two_uses,
	check: broken_after,
	format: shout,
	hover: first_word,
	definition: first_word,
)

fn open_buffer(var server: Server, backend: Backend) Void:
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
		backend,
	)
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":3,\"text\":\"x := 1\\nreturn x\\n\"}}}",
		backend,
	)
	server.publish(backend)

test "references and highlights answer from the index":
	var server = Server(version: "0")
	open_buffer(server, indexed())

	found := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":1,\"character\":7},\"context\":{\"includeDeclaration\":false}}}",
		indexed(),
	)
	expect_equal(
		found.messages[0],
		"{\"jsonrpc\":\"2.0\",\"id\":30,\"result\":[{\"uri\":\"file:///a.ms\",\"range\":{\"start\":{\"line\":1,\"character\":7},\"end\":{\"line\":1,\"character\":8}}}]}",
	)?

	marked := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"textDocument/documentHighlight\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":0,\"character\":0}}}",
		indexed(),
	)
	expect_equal(marked.messages[0].count("\"kind\":2"), 2)?

test "rename answers a versioned edit, and prepareRename the declaration":
	var server = Server(version: "0")
	open_buffer(server, indexed())

	prepared := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"textDocument/prepareRename\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":1,\"character\":7}}}",
		indexed(),
	)
	expect_equal(prepared.messages[0].contains("\"placeholder\":\"x\""), true)?

	renamed := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"textDocument/rename\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":0,\"character\":0},\"newName\":\"count\"}}",
		indexed(),
	)
	message := renamed.messages[0]
	expect_equal(message.contains("\"version\":3"), true)?
	expect_equal(message.count("\"newText\":\"count\""), 2)?

test "a rename is refused when the name is bad, written already, or breaks the buffer":
	var server = Server(version: "0")
	open_buffer(server, indexed())

	ask := "{\"jsonrpc\":\"2.0\",\"id\":34,\"method\":\"textDocument/rename\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"},\"position\":{\"line\":0,\"character\":0},\"newName\":\""
	bad := server.handle(ask.concat("two words\"}}"), indexed())
	expect_equal(bad.messages[0].contains("must be a Manuscript identifier"), true)?

	empty := server.handle(ask.concat("\"}}"), indexed())
	expect_equal(empty.messages[0].contains("new name is empty"), true)?

	// The edit would leave `y := 1` which the stand-in checker rejects.
	broken := server.handle(ask.concat("y\"}}"), indexed())
	expect_equal(
		broken.messages[0].contains("rename would break a.ms: unknown name"),
		true,
	)?
