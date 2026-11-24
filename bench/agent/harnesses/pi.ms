import (
	JsonValue from "@std/data/json.ms",

	Harness, Usage, events, int_at from "./harness.ms",
)

// UNTESTED: pi's JSON event schema is assumed; sums `usage` blocks on assistant
// messages.
export type Pi {
	placeholder Bool = true
}

fn Pi.name() String => "pi"

fn Pi.command(prompt, workspace String, model String?) List[String] {
	var cmd = ["pi", "--mode", "json", "-p", prompt.clone()]
	m := model
	if m != null { cmd = cmd.concat(["--model", m.clone()]) }
	return cmd
}

fn Pi.parse(transcript String) Usage {
	var u = Usage()

	for ev in events(transcript) {
		msg := ev.get("message") or JsonValue.Null
		if (((ev.get("type") or JsonValue.Null).as_string() or "") != "message_end") { continue }
		if ((msg.get("role") or JsonValue.Null).as_string() or "") != "assistant" { continue }

		us := msg.get("usage") or JsonValue.Null
		if us.is_null() { continue }

		u.tokens_in += int_at(us, "input")
		u.tokens_cached += int_at(us, "cacheRead") + int_at(us, "cacheWrite")
		u.tokens_out += int_at(us, "output")
		u.turns += 1

		total := (us.get("cost") or JsonValue.Null).get("total")

		if total != null {
			u.cost_usd += total.as_float() or 0.0
			u.cost_source = "harness"
		}
	}

	return u
}
