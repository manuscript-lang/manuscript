import (
	JsonValue from "@std/data/json.ms",

	Harness, Usage, events, int_at from "./harness.ms",
)

// UNTESTED: written from the documented `codex exec --json` event stream.
export type Codex:
	placeholder Bool = true

fn Codex.name() String => "codex"

fn Codex.command(prompt String, workspace String, model String?) List[String]:
	var cmd = [
		"codex",
		"exec",
		"--json",
		"--dangerously-bypass-approvals-and-sandbox",
		"--skip-git-repo-check",
		"-C",
		workspace.clone(),
	]
	m := model
	if m != null: cmd = cmd.concat(["-m", m.clone()])
	return cmd.concat([prompt.clone()])

// Codex reports no cost; the runner estimates it from pricing.json.
fn Codex.parse(transcript String) Usage:
	var u = Usage()

	for ev in events(transcript):
		if (((ev.get("type") or JsonValue.Null).as_string() or "") != "turn.completed"): continue

		us := ev.get("usage") or JsonValue.Null
		cached := int_at(us, "cached_input_tokens")
		u.tokens_in += int_at(us, "input_tokens") - cached
		u.tokens_cached += cached
		u.tokens_out += int_at(us, "output_tokens")
		u.turns += 1

	return u
