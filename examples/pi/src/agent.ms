// The agent loop: stream a turn, run requested tools, feed results back, repeat until the model stops.
import (
	Ui, NullUi from "./ui.ms",
	Signal from "@std/concurrency/promise.ms",
	JsonValue from "@std/data/json.ms",
	str, obj, arr, flag, str_or, render from "./jsonx.ms",
	ProviderConfig, ToolCall, Turn, stream_turn from "./provider.ms",
	definitions, execute from "./tools.ms",
	Session, append, append_compaction, entries, branch from "./session.ms",
)

export type Agent:
	config: ProviderConfig
	system: String
	tools: List[String]
	history: List[JsonValue]
	session: Session?
	// Id of the newest entry on the active branch; "" before the first message.
	leaf: String
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
			self.leaf = try append(saved, self.leaf, msg)
		self.history.append(msg)

	// Sends a user prompt and runs turns until the model finishes without requesting tools.
	// Raising `stop` ends the turn at the next event; tool calls already requested get an "Aborted" result.
	var fn prompt(
		text: String,
		images: List[JsonValue],
		var ui: Ui,
		stop: Signal
	) String!:
		var blocks = images.clone()
		blocks.append(text_block(text))
		try self.record(message("user", arr(blocks)))

		var final_text = ""
		var turns = 0

		while turns < self.max_turns:
			turns += 1

			turn := try stream_turn(
				self.config, self.system, self.history, definitions(self.tools), var ui,
				stop.clone()
			)
			self.input_tokens += turn.input_tokens
			self.output_tokens += turn.output_tokens
			try self.record(message("assistant", turn.content))
			final_text = turn.text.clone()
			if turn.tool_calls.is_empty(): return ok(final_text)

			var results = List[JsonValue]()

			for call in turn.tool_calls:
				if stop.cancelled():
					results.append(result_block(call.id, "Aborted by user", true))
					continue

				ui.tool(call.name, summarize(call))

				result := execute(call.name, call.input, stop.clone())
				ui.result(call.name, result.is_error, result.text)
				results.append(result_block(call.id, result.text, result.is_error))

			try self.record(message("user", arr(results)))
			if stop.cancelled(): return error(Error("aborted", kind: "ECANCELED"))

		return error(Error("Stopped after {self.max_turns} turns"))

	// Replaces the history with a model-written summary and records a compaction entry.
	var fn compact(focus: String, stop: Signal) String!:
		if self.history.is_empty(): return error(Error("Nothing to compact"))

		var ask = "Summarize the conversation so far so work can continue from the summary alone. Keep: the goal, decisions made, files read or changed, commands run and their outcomes, and open problems."
		if not focus.is_empty(): ask = "{ask} Focus on: {focus}"

		var transcript = self.history.clone()
		transcript.append(message("user", arr([text_block(ask)])))

		var quiet: Ui = NullUi(unused: true)
		turn := try stream_turn(
			self.config, "You write precise summaries of coding sessions.", transcript,
			List[JsonValue](), var quiet, stop
		)
		summary := turn.text.trim()
		if summary.is_empty(): return error(
			Error("The model returned an empty summary")
		)

		if saved := self.session:
			self.leaf = try append_compaction(saved, self.leaf, summary)
		self.history = branch([], "")
		self.history.append(
			message(
				"user",
				arr(
					[
						text_block(
							"The conversation so far was compacted. Summary of what happened:\n\n{summary}"
						)
					]
				)
			)
		)
		return ok(summary)

	// Moves the active branch to entry `id`; the next prompt becomes a sibling of what followed it.
	var fn fork(id: String) Unit!:
		saved := self.session
		if saved.is_none(): return error(
			Error("Sessions are off (--no-session); nothing to fork")
		)

		all := try entries(saved.get(none).path)
		if not all.any(fn e: e.id == id): return error(
			Error("No entry {id}; use /tree to list entries")
		)

		self.history = branch(all, id)
		self.leaf = id.clone()
		return ok(unit)
