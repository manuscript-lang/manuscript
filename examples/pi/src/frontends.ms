// Ui implementations: styled terminal (markdown), plain text, and JSON lines.
import (
	JsonValue from "@std/data/json.ms",
	Ui from "./ui.ms",
	Renderer, new_renderer from "./markdown.ms",
	write_out, write_err, dim, red, Screen, new_screen, read_line from "./tui.ms",
	str, num, flag, obj, render, str_or, int_or from "./jsonx.ms",
)

// Retained-mode terminal front end: the transcript is kept as lines and each change is drawn as a diff.
export type TerminalUi:
	screen: Screen
	// Streaming assistant text and reasoning not yet committed to the transcript.
	text_buffer: String
	thinking_buffer: String

export fn terminal_ui() TerminalUi:
	return TerminalUi(screen: new_screen(), text_buffer: "", thinking_buffer: "")

fn markdown(text: String) String:
	var r = new_renderer()
	first := r.feed(text)
	return "{first}{r.finish()}".trim_end()

impl TerminalUi:
	// Re-renders the streaming component from its buffers and redraws the frame.
	var fn refresh() Unit:
		var shown = ""
		if not self.thinking_buffer.is_empty(): shown = dim(
			self.thinking_buffer.trim_end()
		)
		if not self.text_buffer.is_empty(): shown = "{shown}{if shown.is_empty(): "" else: "\n"}{markdown(self.text_buffer)}"
		self.screen.set_live(shown)
		self.screen.draw([dim("working… Esc to abort")], 0, 0)

	// Moves the finished streaming component into the transcript.
	var fn flush() Unit:
		if not self.thinking_buffer.is_empty(): self.screen.commit(
			dim(self.thinking_buffer.trim_end())
		)
		if not self.text_buffer.is_empty(): self.screen.commit(
			markdown(self.text_buffer)
		)
		self.thinking_buffer = ""
		self.text_buffer = ""
		self.screen.set_live("")

impl Ui for TerminalUi:
	var fn text(piece: String) Unit:
		self.text_buffer = "{self.text_buffer}{piece}"
		self.refresh()

	var fn thinking(piece: String) Unit:
		self.thinking_buffer = "{self.thinking_buffer}{piece}"
		self.refresh()

	var fn tool(name: String, summary: String) Unit:
		self.flush()
		self.screen.commit(dim("▸ {name} {summary}"))
		self.screen.draw([dim("working… Esc to abort")], 0, 0)

	var fn result(name: String, failed: Bool, output: String) Unit:
		lines := output.split("\n")
		shown := lines.take(if failed: 8 else: 3).join("\n")
		more := if lines.length() > 8 or (not failed and lines.length() > 3): "\n…" else: ""
		self.screen.commit(if failed: red("{shown}{more}") else: dim("{shown}{more}"))
		self.screen.draw([dim("working… Esc to abort")], 0, 0)

	var fn event(kind: String, payload: JsonValue) Unit:
		if kind == "resync": self.screen.reset()

	var fn prompt_line(prompt: String, history: List[String], footer: String) String?!:
		return read_line(var self.screen, prompt, history, footer)

	var fn end() Unit:
		self.flush()
		self.screen.commit("")
		self.screen.draw(List[String](), -1, 0)

// Unstyled text for `-p`: the reply on stdout, tool activity on stderr.
export type PlainUi:
	unused: Bool

impl Ui for PlainUi:
	var fn text(piece: String) Unit:
		write_out(piece)

	var fn thinking(piece: String) Unit:
		return unit

	var fn tool(name: String, summary: String) Unit:
		write_err("▸ {name} {summary}\n")

	var fn result(name: String, failed: Bool, output: String) Unit:
		if failed: write_err("{output.take(400)}\n")

	var fn event(kind: String, payload: JsonValue) Unit:
		return unit

	var fn prompt_line(prompt: String, history: List[String], footer: String) String?!:
		return ok(none)

	var fn end() Unit:
		write_out("\n")

// pi-compatible JSON event lines on stdout, for programs driving pi: message_update events carry the whole
// partial assistant message, as pi's do.
export type JsonUi:
	// api, provider and model of the running turn.
	meta: JsonValue
	partial: String
	started: Bool
	timestamp: Int
	// The tool call being streamed: id, name and argument JSON so far.
	tool_id: String
	tool_name: String
	tool_json: String

export fn json_ui() JsonUi:
	return JsonUi(
		meta: JsonValue.Null, partial: "", started: false, timestamp: 0, tool_id: "",
		tool_name: "", tool_json: ""
	)

fn emit(kind: String, fields: Map[String, JsonValue]) Unit:
	var record = Map[String, JsonValue]()
	record.add("type", str(kind))
	for entry in fields.entries(): record.add(entry.key.clone(), entry.value.clone())
	write_out("{render(obj(record)).get("\{\}")}\n")

export fn emit_response(
	command: String,
	success: Bool,
	fields: Map[String, JsonValue]
) Unit:
	var record = fields.clone()
	record.add("command", str(command))
	record.add("success", flag(success))
	emit("response", record)

fn zero_usage() JsonValue:
	var cost = Map[String, JsonValue]()
	for key in ["input", "output", "cacheRead", "cacheWrite", "total"]: cost.add(
		key.clone(), num(0)
	)

	var usage = Map[String, JsonValue]()
	for key in ["input", "output", "cacheRead", "cacheWrite", "totalTokens"]: usage.add(
		key.clone(), num(0)
	)
	usage.add("cost", obj(cost))
	return obj(usage)

impl JsonUi:
	// The assistant message as it stands, in pi's shape.
	fn snapshot() JsonValue:
		var block = Map[String, JsonValue]()
		block.add("type", str("text"))
		block.add("text", str(self.partial))
		block.add("index", num(0))

		var content = [obj(block)]

		if not self.tool_name.is_empty():
			var call = Map[String, JsonValue]()
			call.add("type", str("toolCall"))
			call.add("id", str(self.tool_id))
			call.add("name", str(self.tool_name))
			call.add("partialJson", str(self.tool_json))
			call.add("index", num(1))
			content = [obj(call)]

		var message = Map[String, JsonValue]()
		message.add("role", str("assistant"))
		message.add("content", JsonValue.ArrayValue(content))
		for key in ["api", "provider", "model"]: message.add(
			key.clone(), str(str_or(self.meta, key, ""))
		)
		message.add("usage", zero_usage())
		message.add("stopReason", str("stop"))
		message.add("timestamp", num(self.timestamp))
		return obj(message)

	fn update(kind: String, delta: String) Unit:
		partial := self.snapshot()
		var inner = Map[String, JsonValue]()
		inner.add("type", str(kind))
		inner.add("contentIndex", num(0))
		if not delta.is_empty(): inner.add("delta", str(delta))
		inner.add("partial", partial.clone())

		var f = Map[String, JsonValue]()
		f.add("assistantMessageEvent", obj(inner))
		f.add("message", partial)
		emit("message_update", f)

impl Ui for JsonUi:
	var fn text(piece: String) Unit:
		if not self.started:
			self.started = true

			var begin = Map[String, JsonValue]()
			begin.add("message", self.snapshot())
			emit("message_start", begin)
			self.update("text_start", "")

		self.partial = "{self.partial}{piece}"
		self.update("text_delta", piece)

	var fn thinking(piece: String) Unit:
		var f = Map[String, JsonValue]()
		var inner = Map[String, JsonValue]()
		inner.add("type", str("thinking_delta"))
		inner.add("contentIndex", num(0))
		inner.add("delta", str(piece))
		f.add("assistantMessageEvent", obj(inner))
		emit("message_update", f)

	var fn tool(name: String, summary: String) Unit:
		return unit

	var fn result(name: String, failed: Bool, output: String) Unit:
		return unit

	var fn event(kind: String, payload: JsonValue) Unit:
		if kind == "toolcall_start":
			info := str_or(payload, "info", "|").split("|")
			self.tool_id = info[0].clone()
			self.tool_name = info.get(1, "")
			self.tool_json = ""

			var begin = Map[String, JsonValue]()
			begin.add("message", self.snapshot())
			emit("message_start", begin)
			self.update("toolcall_start", "")
			return

		if kind == "toolcall_delta":
			self.tool_json = "{self.tool_json}{str_or(payload, "delta", "")}"
			self.update("toolcall_delta", str_or(payload, "delta", ""))
			return

		if kind == "turn_start":
			self.tool_name = ""
			self.tool_json = ""
			self.meta = payload.get("meta").get(JsonValue.Null).clone()
			self.partial = ""
			self.started = false
			self.timestamp = int_or(payload, "timestamp", 0)

		var f = payload.as_map().get(Map[String, JsonValue]()).clone()
		if kind == "turn_start": f.remove("meta")
		if kind == "turn_start": f.remove("timestamp")
		emit(kind, f)

	var fn prompt_line(prompt: String, history: List[String], footer: String) String?!:
		return ok(none)

	var fn end() Unit:
		return unit
