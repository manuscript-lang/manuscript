// The agent loop: stream a turn, run requested tools, feed results back, repeat until the model stops.
import (
	JsonValue from "@std/data/json.ms",
	str, obj, arr, flag, str_or, render from "./jsonx.ms",
	ProviderConfig, ToolCall, Turn, stream_turn from "./provider.ms",
	definitions, execute from "./tools.ms",
	Session, append from "./session.ms",
)

// Callbacks the UI supplies; the loop never prints on its own.
export type Events:
	on_text: fn(String) Unit
	on_tool: fn(String, String) Unit
	on_result: fn(String, Bool, String) Unit

export type Agent:
	config: ProviderConfig
	system: String
	tools: List[String]
	history: List[JsonValue]
	session: Session?
	input_tokens: Int
	output_tokens: Int
	max_turns: Int = 50

fn message(role: String, content: JsonValue) JsonValue:
	var m = Map[String, JsonValue]()
	m.add("role", str(role))
	m.add("content", content.clone())
	return obj(m)

fn text_block(text: String) JsonValue:
	var b = Map[String, JsonValue]()
	b.add("type", str("text"))
	b.add("text", str(text))
	return obj(b)

fn result_block(id: String, text: String, is_error: Bool) JsonValue:
	var b = Map[String, JsonValue]()
	b.add("type", str("tool_result"))
	b.add("tool_use_id", str(id))
	b.add("content", str(text))
	if is_error: b.add("is_error", flag(true))
	return obj(b)

// One-line description of a call for display: the command, path or pattern.
export fn summarize(call: ToolCall) String:
	for key in ["command", "path", "pattern"]:
		value := str_or(call.input, key, "")
		if not value.is_empty(): return value

	return ""

impl Agent:
	var fn record(msg: JsonValue) Unit!:
		if saved := self.session:
			try append(saved, msg)
		self.history.append(msg)

	// Sends a user prompt and runs turns until the model finishes without requesting tools.
	var fn prompt(text: String, events: Events) String!:
		try self.record(message("user", arr([text_block(text)])))

		var final_text = ""
		var turns = 0

		while turns < self.max_turns:
			turns += 1

			turn := try stream_turn(
				self.config, self.system, self.history, definitions(self.tools),
				events.on_text
			)
			self.input_tokens += turn.input_tokens
			self.output_tokens += turn.output_tokens
			try self.record(message("assistant", turn.content))
			final_text = turn.text.clone()
			if turn.tool_calls.is_empty(): return ok(final_text)

			var results = List[JsonValue]()

			for call in turn.tool_calls:
				events.on_tool(call.name, summarize(call))

				result := execute(call.name, call.input)
				events.on_result(call.name, result.is_error, result.text)
				results.append(result_block(call.id, result.text, result.is_error))

			try self.record(message("user", arr(results)))

		return error(Error("Stopped after {self.max_turns} turns"))
