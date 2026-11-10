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

	var fn end() Unit:
		return unit
