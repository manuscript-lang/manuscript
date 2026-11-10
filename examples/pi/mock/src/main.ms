// A scripted stand-in for the Anthropic and OpenAI streaming APIs, for testing pi offline.
// Prompts drive it: "bash:CMD", "read:PATH", "write:PATH|TEXT", "edit:PATH|OLD|NEW"; a tool result is echoed back; anything else is echoed.
import JsonValue, parse, stringify from "@std/data/json.ms"
import headers, HttpExchange, HttpServerOptions, read_body from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import arguments from "@std/os/env.ms"

fn field(doc: JsonValue, key: String) String:
	if v := doc.get(key):
		if s := v.as_string(): return s
	return ""

// The text of the newest user message and whether it carries a tool result.
fn last_user(body: JsonValue) List[String]:
	messages := body.get("messages").get(JsonValue.Null).as_list().get([])
	var found = ["", ""]
	for message in messages:
		if field(message, "role") == "user":
			if blocks := message.get("content"):
				for block in blocks.as_list().get([]):
					if field(block, "type") == "tool_result": found = ["", field(block, "content")]
					if field(block, "type") == "text": found = [field(block, "text"), ""]
		if field(message, "role") == "tool": found = ["", field(message, "content")]
		if field(message, "role") == "user" and message.get("content").get(JsonValue.Null).as_string().is_some():
			found = [field(message, "content"), ""]
	return found

fn sse(event: String, data: String) String:
	return "event: {event}\ndata: {data}\n\n"

fn json_text(value: String) String:
	return stringify(value).get("\"\"")

fn tool_json(text: String) List[String]:
	// Returns [name, input-json] for a scripted prompt, or [] when it is plain text.
	if text.starts_with("bash:"): return ["bash", "\{\"command\":{json_text(text.drop(5))}\}"]
	if text.starts_with("read:"): return ["read", "\{\"path\":{json_text(text.drop(5))}\}"]
	if text.starts_with("write:"):
		parts := text.drop(6).split("|")
		return ["write", "\{\"path\":{json_text(parts[0])},\"content\":{json_text(parts.get(1, ""))}\}"]
	if text.starts_with("edit:"):
		parts := text.drop(5).split("|")
		return ["edit", "\{\"path\":{json_text(parts[0])},\"oldText\":{json_text(parts.get(1, ""))},\"newText\":{json_text(parts.get(2, ""))}\}"]
	return []

fn anthropic_stream(text: String, result: String) String:
	var out = sse("message_start", "\{\"type\":\"message_start\",\"message\":\{\"usage\":\{\"input_tokens\":12\}\}\}")
	call := tool_json(text)
	if not result.is_empty() or call.is_empty():
		reply := if result.is_empty(): "echo: {text}" else: "tool said: {result}"
		out = "{out}{sse("content_block_start", "\{\"type\":\"content_block_start\",\"index\":0,\"content_block\":\{\"type\":\"text\",\"text\":\"\"\}\}")}"
		for word in reply.split(" "):
			out = "{out}{sse("content_block_delta", "\{\"type\":\"content_block_delta\",\"index\":0,\"delta\":\{\"type\":\"text_delta\",\"text\":{json_text("{word} ")}\}\}")}"
		out = "{out}{sse("message_delta", "\{\"type\":\"message_delta\",\"delta\":\{\"stop_reason\":\"end_turn\"\},\"usage\":\{\"output_tokens\":7\}\}")}"
		return "{out}{sse("message_stop", "\{\"type\":\"message_stop\"\}")}"
	out = "{out}{sse("content_block_start", "\{\"type\":\"content_block_start\",\"index\":0,\"content_block\":\{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"{call[0]}\",\"input\":\{\}\}\}")}"
	half := call[1].length() / 2
	first := call[1].take(half)
	second := call[1].drop(half)
	out = "{out}{sse("content_block_delta", "\{\"type\":\"content_block_delta\",\"index\":0,\"delta\":\{\"type\":\"input_json_delta\",\"partial_json\":{json_text(first)}\}\}")}"
	out = "{out}{sse("content_block_delta", "\{\"type\":\"content_block_delta\",\"index\":0,\"delta\":\{\"type\":\"input_json_delta\",\"partial_json\":{json_text(second)}\}\}")}"
	out = "{out}{sse("message_delta", "\{\"type\":\"message_delta\",\"delta\":\{\"stop_reason\":\"tool_use\"\},\"usage\":\{\"output_tokens\":9\}\}")}"
	return "{out}{sse("message_stop", "\{\"type\":\"message_stop\"\}")}"

fn openai_stream(text: String, result: String) String:
	call := tool_json(text)
	if not result.is_empty() or call.is_empty():
		reply := if result.is_empty(): "echo: {text}" else: "tool said: {result}"
		var out = ""
		for word in reply.split(" "):
			out = "{out}data: \{\"choices\":[\{\"delta\":\{\"content\":{json_text("{word} ")}\}\}]\}\n\n"
		return "{out}data: \{\"choices\":[\{\"delta\":\{\},\"finish_reason\":\"stop\"\}],\"usage\":\{\"prompt_tokens\":12,\"completion_tokens\":7\}\}\n\ndata: [DONE]\n\n"
	args := json_text(call[1])
	return "data: \{\"choices\":[\{\"delta\":\{\"tool_calls\":[\{\"index\":0,\"id\":\"call_1\",\"function\":\{\"name\":\"{call[0]}\",\"arguments\":{args}\}\}]\}\}]\}\n\ndata: \{\"choices\":[\{\"delta\":\{\},\"finish_reason\":\"tool_calls\"\}]\}\n\ndata: [DONE]\n\n"

fn handle(var exchange: HttpExchange) Unit!:
	path := exchange.path()
	raw := try read_body(var exchange, 16777216)
	body := try parse(raw.decode_utf8().get("\{\}"))
	found := last_user(body)
	var sent = headers()
	try sent.append("Content-Type", "text/event-stream")
	try exchange.send_headers(200, sent)
	payload := if path.ends_with("/messages"): anthropic_stream(found[0], found[1]) else: openai_stream(found[0], found[1])
	try exchange.write(payload)

fn main() Unit!:
	address := arguments().get(0, "127.0.0.1:8099")
	server := try serve(address, handle, HttpServerOptions())
	print("mock llm listening on {server.address()}")
	try server.wait()
