// The Manuscript language server on standard input and output:
// `ms run src/lsp/main.ms`. Messages are handled in order; the diagnostics of every
// document that changed while a burst of input was handled are sent once, after the
// burst.
import (
	Bytes from "@std/bytes.ms",
	stderr, stdin, stdout_bytes from "@std/io/io.ms",

	analyze_in from "./analysis.ms",
	check_document from "./check.ms",
	format_document from "./format.ms",
	Framer, encode from "./frame.ms",
	definition, hover from "./navigate.ms",
	Backend, Found, Next, Server from "./server.ms",
)

fn hover_at(path: String, text: String, offset: Int) Found?:
	facts := analyze_in(path, text, [])
	if facts.is_error(): return none

	shown := hover(facts.get(), text, offset)?
	return Found(text: shown.text, start: shown.span.start, end: shown.span.end)

fn definition_at(path: String, text: String, offset: Int) Found?:
	facts := analyze_in(path, text, [])
	if facts.is_error(): return none

	target := definition(facts.get(), text, offset)?
	return Found(text: "", start: target.start, end: target.end)

fn send(messages: List[String]) Void!:
	var out = stdout_bytes()
	for message in messages:
		out.write(encode(message))?
	out.flush()?

fn serve() Int!:
	var input = stdin()
	var framer = Framer()
	var server = Server(version: "dev")
	backend := Backend(
		check: check_document,
		format: format_document,
		hover: hover_at,
		definition: definition_at,
	)

	for chunk in input:
		framer.push(chunk)

		while true:
			frame := framer.next_frame()?
			body := frame.get_or("".to_bytes())
			if frame.is_none(): break

			handled := server.handle(body.decode_utf8().get_or(""), backend)
			send(handled.messages)?
			if handled.next == Next.Stop: return ok(0)
			if handled.next == Next.StopFailed: return ok(1)

		send(server.publish(backend))?

	return ok(0)

fn main() Int:
	status := serve()

	if status.is_error():
		var eprint = stderr()
		eprint.write(f"ms-lsp: {status.err().message}\n").get_or(void)
		return 1

	return status.get()
