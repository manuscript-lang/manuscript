import JsonValue from "@std/data/json.ms"

// What the agent reports while it works. Front ends implement it: styled terminal, plain text, JSON lines.
export interface Ui:
	// A piece of the assistant's reply.
	var fn text(piece: String) Unit
	// A piece of the model's reasoning.
	var fn thinking(piece: String) Unit
	// A tool call is about to run.
	var fn tool(name: String, summary: String) Unit
	// A tool call finished.
	var fn result(name: String, failed: Bool, output: String) Unit
	// A lifecycle event (agent_start, turn_start, message_start, message_end, tool_execution_*, turn_end, agent_end) with its payload fields.
	var fn event(kind: String, payload: JsonValue) Unit
	// Reads the next prompt; none ends the session. Front ends without an editor return none.
	var fn prompt_line(prompt: String, history: List[String], footer: String) String?!
	// The turn ended; flush anything buffered.
	var fn end() Unit

// Discards everything; used for internal model calls such as compaction.
export type NullUi:
	unused: Bool

impl Ui for NullUi:
	var fn text(piece: String) Unit:
		return unit

	var fn thinking(piece: String) Unit:
		return unit

	var fn tool(name: String, summary: String) Unit:
		return unit

	var fn result(name: String, failed: Bool, output: String) Unit:
		return unit

	var fn event(kind: String, payload: JsonValue) Unit:
		return unit

	var fn prompt_line(prompt: String, history: List[String], footer: String) String?!:
		return ok(none)

	var fn end() Unit:
		return unit
