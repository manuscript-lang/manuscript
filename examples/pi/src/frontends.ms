// Ui implementations: styled terminal (markdown), plain text, and JSON lines.
import (
	JsonValue from "@std/data/json.ms",
	Ui from "./ui.ms",
	Renderer, new_renderer from "./markdown.ms",
	write_out, write_err, dim, red from "./tui.ms",
	str, num, flag, obj, render from "./jsonx.ms",
)

// Markdown-rendered terminal output with dimmed reasoning and tool lines.
export type TerminalUi:
	renderer: Renderer
	reasoning: Bool

export fn terminal_ui() TerminalUi:
	return TerminalUi(renderer: new_renderer(), reasoning: false)

impl TerminalUi:
	var fn close_reasoning() Unit:
		if self.reasoning:
			write_out("\n")
			self.reasoning = false

impl Ui for TerminalUi:
	var fn text(piece: String) Unit:
		self.close_reasoning()
		write_out(self.renderer.feed(piece))

	var fn thinking(piece: String) Unit:
		self.reasoning = true
		write_out(dim(piece))

	var fn tool(name: String, summary: String) Unit:
		self.close_reasoning()
		write_out(self.renderer.finish())
		write_out(dim("▸ {name} {summary}\n"))

	var fn result(name: String, failed: Bool, output: String) Unit:
		lines := output.split("\n")
		shown := lines.take(if failed: 8 else: 3).join("\n")
		more := if lines.length() > 8 or (not failed and lines.length() > 3): "\n…" else: ""
		write_out(if failed: red("{shown}{more}\n") else: dim("{shown}{more}\n"))

	var fn end() Unit:
		self.close_reasoning()
		write_out("{self.renderer.finish()}\n")

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

	var fn end() Unit:
		write_out("\n")

// One JSON object per line on stdout, for programs driving pi.
export type JsonUi:
	unused: Bool

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

impl Ui for JsonUi:
	var fn text(piece: String) Unit:
		var f = Map[String, JsonValue]()
		f.add("delta", str(piece))
		emit("text", f)

	var fn thinking(piece: String) Unit:
		var f = Map[String, JsonValue]()
		f.add("delta", str(piece))
		emit("thinking", f)

	var fn tool(name: String, summary: String) Unit:
		var f = Map[String, JsonValue]()
		f.add("name", str(name))
		f.add("summary", str(summary))
		emit("tool_start", f)

	var fn result(name: String, failed: Bool, output: String) Unit:
		var f = Map[String, JsonValue]()
		f.add("name", str(name))
		f.add("isError", flag(failed))
		f.add("output", str(output))
		emit("tool_end", f)

	var fn end() Unit:
		emit("agent_end", Map[String, JsonValue]())
