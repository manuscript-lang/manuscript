import (
	JsonValue from "@std/data/json.ms",

	Harness, Usage, events, int_at from "./harness.ms",
)

export type ClaudeCode:
	placeholder: Bool = true

fn ClaudeCode.name() String: "claude_code"

fn ClaudeCode.command(prompt: String, workspace: String, model: String?) List[String]:
	var cmd = [
		"claude",
		"-p",
		prompt.clone(),
		"--output-format",
		"stream-json",
		"--verbose",
		"--dangerously-skip-permissions",
		"--no-session-persistence",
	]
	if m := model: cmd = cmd.concat(["--model", m.clone()])
	return cmd

fn ClaudeCode.parse(transcript: String) Usage:
	for ev in events(transcript).reversed():
		if ev.get("type").get_or(JsonValue.Null).as_string().get_or("") != "result": continue

		u := ev.get("usage").get_or(JsonValue.Null)
		return Usage(
			int_at(u, "input_tokens"),
			int_at(u, "cache_read_input_tokens") + int_at(
				u,
				"cache_creation_input_tokens",
			),
			int_at(u, "output_tokens"),
			int_at(ev, "num_turns"),
			ev.get("total_cost_usd").get_or(
				JsonValue.Null
			).as_float().get_or(0.0),
			"harness",
		)

	return Usage()
