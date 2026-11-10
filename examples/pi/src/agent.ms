// The agent loop: stream a turn, run requested tools, feed results back, repeat until the model stops.
import (
	now from "@std/time.ms",
	num, int_or from "./jsonx.ms",
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

fn now_ms() Int:
	stamp := now()
	return stamp.unix_seconds() * 1000 + stamp.nanos / 1000000

fn with_time(m: JsonValue, ts: Int) JsonValue:
	var fields = m.as_map().get(Map[String, JsonValue]())
	fields.add("timestamp", num(ts))
	return obj(fields)

fn usage_of(turn: Turn) JsonValue:
	var cost = Map[String, JsonValue]()
	for key in ["input", "output", "cacheRead", "cacheWrite", "total"]: cost.add(
		key.clone(), num(0)
	)

	var usage = Map[String, JsonValue]()
	usage.add("input", num(turn.input_tokens))
	usage.add("output", num(turn.output_tokens))
	usage.add("cacheRead", num(0))
	usage.add("cacheWrite", num(0))
	usage.add("totalTokens", num(turn.input_tokens + turn.output_tokens))
	usage.add("cost", obj(cost))
	return obj(usage)

fn stop_label(reason: String) String:
	if reason == "tool_use": return "toolUse"
	if reason == "max_tokens": return "length"

	return "stop"

// The assistant message as pi stores and reports it: content plus api, provider, model, usage and stop reason.
fn assistant_stored(cfg: ProviderConfig, turn: Turn, ts: Int) JsonValue:
	var m = Map[String, JsonValue]()
	m.add("role", str("assistant"))
	m.add("content", turn.content.clone())
	m.add("api", str("{cfg.api}-messages"))
	m.add("provider", str(cfg.name))
	m.add("model", str(cfg.model))
	m.add("usage", usage_of(turn))
	m.add("stopReason", str(stop_label(turn.stop_reason)))
	m.add("timestamp", num(ts))
	return obj(m)

fn result_stored(call: ToolCall, text: String, failed: Bool, ts: Int) JsonValue:
	var m = Map[String, JsonValue]()
	m.add("role", str("toolResult"))
	m.add("toolCallId", str(call.id))
	m.add("toolName", str(call.name))
	m.add("content", arr([text_block(text)]))
	m.add("isError", flag(failed))
	m.add("timestamp", num(ts))
	return obj(m)

fn wrap(fields: List[List[String]], extra: Map[String, JsonValue]) JsonValue:
	var m = extra.clone()
	for pair in fields: m.add(pair[0].clone(), str(pair[1]))
	return obj(m)

fn event_message(message: JsonValue) JsonValue:
	var f = Map[String, JsonValue]()
	f.add("message", message.clone())
	return obj(f)

fn content_of(text: String) Map[String, JsonValue]:
	var m = Map[String, JsonValue]()
	m.add("content", arr([text_block(text)]))
	return m

impl Agent:
	// Records `stored` in the session (with pi's extra fields) and `clean` in the API history.
	var fn record(clean: JsonValue, stored: JsonValue) Unit!:
		if saved := self.session:
			self.leaf = try append(saved, self.leaf, stored)
		self.history.append(clean)

	// Sends a user prompt and runs turns until the model finishes without requesting tools.
	// Raising `stop` ends the turn at the next event; tool calls already requested get an "Aborted" result.
	// Lifecycle events follow pi's: agent_start, turn_start, message_*, tool_execution_*, turn_end, agent_end.
	var fn prompt(
		text: String,
		images: List[JsonValue],
		var ui: Ui,
		stop: Signal
	) String!:
		var blocks = images.clone()
		blocks.append(text_block(text))

		var run = List[JsonValue]()
		ui.event("agent_start", JsonValue.ObjectValue(Map[String, JsonValue]()))

		user_stored := with_time(message("user", arr(blocks.clone())), now_ms())
		ui.event("message_start", event_message(user_stored))
		try self.record(message("user", arr(blocks)), user_stored)
		ui.event("message_end", event_message(user_stored))
		run.append(user_stored)

		var final_text = ""
		var turns = 0

		while turns < self.max_turns:
			turns += 1

			started := now_ms()
			var begin = Map[String, JsonValue]()
			var meta = Map[String, JsonValue]()
			meta.add("api", str("{self.config.api}-messages"))
			meta.add("provider", str(self.config.name))
			meta.add("model", str(self.config.model))
			begin.add("meta", obj(meta))
			begin.add("timestamp", num(started))
			ui.event("turn_start", obj(begin))

			turn := try stream_turn(
				self.config, self.system, self.history, definitions(self.tools), var ui,
				stop.clone()
			)
			self.input_tokens += turn.input_tokens
			self.output_tokens += turn.output_tokens

			assistant := assistant_stored(self.config, turn, started)
			try self.record(message("assistant", turn.content), assistant)
			ui.event("message_end", event_message(assistant))
			run.append(assistant.clone())
			final_text = turn.text.clone()

			var results = List[JsonValue]()
			var stored_results = List[JsonValue]()

			for call in turn.tool_calls:
				var tool_fields = Map[String, JsonValue]()
				tool_fields.add("toolCallId", str(call.id))
				tool_fields.add("toolName", str(call.name))
				tool_fields.add("args", call.input.clone())

				if stop.cancelled():
					results.append(result_block(call.id, "Aborted by user", true))
					stored_results.append(
						result_stored(
							call, "Aborted by user", true, now_ms()
						)
					)
					continue

				ui.tool(call.name, summarize(call))
				ui.event("tool_execution_start", obj(tool_fields.clone()))

				result := execute(call.name, call.input, stop.clone())
				ui.result(call.name, result.is_error, result.text)

				var partial = tool_fields.clone()
				partial.add("partialResult", obj(content_of(result.text)))
				ui.event("tool_execution_update", obj(partial))

				var finished = tool_fields.clone()
				finished.add("result", obj(content_of(result.text)))
				finished.add("isError", flag(result.is_error))
				ui.event("tool_execution_end", obj(finished))
				results.append(result_block(call.id, result.text, result.is_error))

				tool_message := result_stored(
					call, result.text, result.is_error, now_ms()
				)
				ui.event("message_start", event_message(tool_message))
				ui.event("message_end", event_message(tool_message))
				stored_results.append(tool_message)

			if not results.is_empty():
				clean := message("user", arr(results))
				for stored in stored_results:
					if saved := self.session:
						self.leaf = try append(saved, self.leaf, stored)
				self.history.append(clean)
				run.extend(stored_results)

			var ending = Map[String, JsonValue]()
			ending.add("message", assistant)
			ending.add("toolResults", arr(stored_results))
			ui.event("turn_end", obj(ending))

			if turn.tool_calls.is_empty():
				var done = Map[String, JsonValue]()
				done.add("messages", arr(run))
				ui.event("agent_end", obj(done))
				return ok(final_text)

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
