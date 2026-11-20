// The language server session: one decoded message in, the messages to send out. It
// follows crates/ms-lsp/src/server.rs for the protocol rules: error codes, the
// initialize and shutdown order, and incremental document sync with UTF-16 positions.
// Diagnostics come from `ms check --json` (see check.ms) until the C checker feeds
// facts directly.
import (
	JsonValue, parse from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

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
	Position, replace_range from "./text.ms",
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
fn var Server.handle(body: String, check: fn(String, String) List[JsonValue]) Outcome:
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
		out.messages.extend(self.publish(check))

	var result = JsonValue.Null
	var known = true

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
	else: known = false

	if request_id := id:
		if known: out.messages.append(result_message(request_id, result))
		else: out.messages.append(
			error_message(request_id, -32601, "method not supported")
		)

	return out

// The messages that bring the diagnostics of every changed open document up to date,
// using `check` to compute the diagnostics of one document.
fn var Server.publish(check: fn(String, String) List[JsonValue]) List[String]:
	var messages: List[String] = []
	pending := self.dirty.clone()
	self.dirty = []

	for uri in pending:
		if document := self.documents.get(uri):
			var found: List[JsonValue] = []
			if is_file(uri): found = check(filename(uri), document.text)
			messages.append(diagnostics_message(uri, found, document.version))

	return messages

fn no_diagnostics(path: String, source: String) List[JsonValue]: []

fn initialized_server() Server:
	var server = Server(version: "0.0.0")
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
		no_diagnostics,
	)
	return server

test "requests before initialize are refused":
	var server = Server()
	out := server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"textDocument/hover\"}",
		no_diagnostics,
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
		no_diagnostics,
	)
	expect_equal(out.messages.length(), 1)?
	expect_equal(out.messages[0].contains("\"textDocumentSync\":2"), true)?
	expect_equal(out.messages[0].contains("\"version\":\"1.2.3\""), true)?

test "bad input gets the JSON-RPC errors":
	var server = initialized_server()
	expect_equal(
		server.handle("{", no_diagnostics).messages[0].contains("-32700"),
		true,
	)?
	expect_equal(
		server.handle("[]", no_diagnostics).messages[0].contains("-32600"),
		true,
	)?
	expect_equal(
		server.handle(
			"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"nope\"}",
			no_diagnostics,
		).messages[0].contains("-32601"),
		true,
	)?
	expect_equal(
		server.handle(
			"{\"jsonrpc\":\"2.0\",\"method\":\"nope\"}",
			no_diagnostics,
		).messages,
		[],
	)?

test "shutdown then exit stops cleanly, exit alone fails":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}",
		no_diagnostics,
	)

	out := server.handle("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", no_diagnostics)
	expect_equal(out.next, Next.Stop)?

	var other = initialized_server()
	expect_equal(
		other.handle(
			"{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}",
			no_diagnostics,
		).next,
		Next.StopFailed,
	)?

test "incremental changes edit the open document":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"ab\\ncd\"}}}",
		no_diagnostics,
	)
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":2},\"contentChanges\":[{\"range\":{\"start\":{\"line\":0,\"character\":1},\"end\":{\"line\":1,\"character\":1}},\"text\":\"X\"}]}}",
		no_diagnostics,
	)
	expect_equal(server.documents.get("file:///a.ms").get().text, "aXd")?
	expect_equal(server.documents.get("file:///a.ms").get().version, 2)?

	messages := server.publish(no_diagnostics)
	expect_equal(messages.length(), 1)?
	expect_equal(messages[0].contains("\"version\":2"), true)?

test "closing a document clears its diagnostics":
	var server = initialized_server()
	server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\",\"version\":1,\"text\":\"x\"}}}",
		no_diagnostics,
	)

	out := server.handle(
		"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.ms\"}}}",
		no_diagnostics,
	)
	expect_equal(out.messages.length(), 1)?
	expect_equal(out.messages[0].contains("\"diagnostics\":[]"), true)?
	expect_equal(server.publish(no_diagnostics), [])?
