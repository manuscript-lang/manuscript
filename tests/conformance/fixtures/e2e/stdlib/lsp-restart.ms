// conform: tags=testing,tier-io
// conform: phase=test
// conform: timeout=60
import (
	Bytes, join from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
	lines from "@std/io/steps.ms",
	parse_int from "@std/math/math.ms",
	environment, working_directory from "@std/os/env.ms",
	SpawnOptions, send_signal, spawn from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	within from "./support/conn.ms",
)

// The language server survives the death of its worker: the supervisor starts a new one
// and replays the open document, so a request after the kill is answered from it. The
// conformance runner names the ms it tests in `MS_UNDER_TEST`. `MS_LSP_LOG` makes the
// supervisor report each worker's process id on standard error.

// `body` with its `@URI@` replaced by the document's URI.
fn at(body: String, uri: String) String:
	return body.replace("@URI@", uri)

fn frame(body: String) Bytes:
	size := body.to_bytes().length()
	return f"Content-Length: {size}\r\n\r\n{body}".to_bytes()

// Reads standard output until the text holds `needle`.
fn wait_for(var output: ReadStream[Bytes], seen: String, needle: String) String!:
	var text = seen.clone()

	while not text.contains(needle):
		chunk := within(output, 20.seconds())?

		if bytes := chunk:
			text += bytes.decode_utf8() or ""
		else:
			break

	return ok(text)

// The process id in the next `ms-lsp: worker N started` line.
fn worker_pid(var report: ReadStream[String]) Int!:
	line := within(report, 20.seconds())?
	text := line or ""
	parts := text.split_once("worker ")

	if found := parts:
		number := found.after.split_once(" started")
		if rest := number: return parse_int(rest.before)

	return ok(0 - 1)

test "a killed worker is replaced and the open document is replayed":
	ms := environment()?.get("MS_UNDER_TEST") or "ms"
	options := SpawnOptions(env: {"MS_LSP_LOG": "1"})
	var child = spawn(ms, ["lsp"], options)?
	var report = lines(child.stderr())
	var output = child.stdout()
	var input = child.stdin()
	here := working_directory()?.replace("\\", "/")
	uri := if here.starts_with("/"): f"file://{here}/main.ms" else: f"file:///{here}/main.ms"
	first := worker_pid(report)?
	expect_true(first > 0)?
	input.write(
		frame(
			at(
				"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}",
				uri,
			)
		)
	)?
	input.write(
		frame(
			at(
				"{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}",
				uri,
			)
		)
	)?
	input.write(
		frame(
			at(
				"{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"@URI@\",\"languageId\":\"manuscript\",\"version\":1,\"text\":\"fn answer() Int:\\n\\treturn 1\\n\"}}}",
				uri,
			)
		)
	)?
	input.write(
		frame(
			at(
				"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"@URI@\"}}}",
				uri,
			)
		)
	)?
	input.flush()?

	before := wait_for(output, "", "\"name\":\"answer\"")?
	expect_true(before.contains("\"name\":\"answer\""))?
	send_signal(first, 9)?

	second := worker_pid(report)?
	expect_true(second > 0)?
	expect_true(second != first)?
	input.write(
		frame(
			at(
				"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"@URI@\"}}}",
				uri,
			)
		)
	)?
	input.flush()?

	after := wait_for(output, "", "\"name\":\"answer\"")?
	expect_true(after.contains("\"name\":\"answer\""))?
	input.write(
		frame(at("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\"}", uri))
	)?
	input.write(frame(at("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", uri)))?
	input.flush()?
	expect_equal(child.wait(timeout: 20.seconds())?, 0)?
