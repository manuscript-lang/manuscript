import JsonValue from "@std/data/json.ms"
import Harness, Usage, events, int_at from "./harness.ms"

# UNTESTED: pi's JSON event schema is assumed; sums `usage` blocks on assistant messages.
export type Pi:
    placeholder: Bool = true

impl Harness for Pi:
    fn name() String: "pi"

    fn command(prompt: String, model: String?, workspace: String) List[String]:
        var cmd = ["pi", "--mode", "json", "-p", prompt.clone()]
        if let m = model: cmd = cmd.concat(["--model", m.clone()])
        return cmd

    fn parse(transcript: String) Usage:
        var u = Usage()

        for ev in events(transcript):
            let msg = ev.get("message").get(JsonValue.Null)
            if ev.get("type").get(JsonValue.Null).as_string().get("") != "message_end": continue
            if msg.get("role").get(JsonValue.Null).as_string().get("") != "assistant": continue

            let us = msg.get("usage").get(JsonValue.Null)
            if us.is_null(): continue

            u.tokens_in += int_at(us, "input")
            u.tokens_cached += int_at(us, "cacheRead") + int_at(us, "cacheWrite")
            u.tokens_out += int_at(us, "output")
            u.turns += 1

            if let total = us.get("cost").get(JsonValue.Null).get("total"):
                u.cost_usd += total.as_float().get(0.0)
                u.cost_source = "harness"

        return u
