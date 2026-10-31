import JsonValue from "@std/json.ms"
import Harness, Usage, events, int_at from "./harness.ms"

export type ClaudeCode:
    placeholder: Bool = true

impl Harness for ClaudeCode:
    fn name() String: "claude_code"

    fn command(prompt: String, model: String?, workspace: String) List[String]:
        var cmd = [
            "claude", "-p", prompt.clone(), "--output-format", "stream-json",
            "--verbose", "--dangerously-skip-permissions", "--no-session-persistence"
        ]
        if let m = model: cmd = cmd.concat(["--model", m.clone()])
        return cmd

    fn parse(transcript: String) Usage:
        for ev in events(transcript).reversed():
            if ev.get("type").get(JsonValue.Null).as_string().get("") != "result": continue

            let u = ev.get("usage").get(JsonValue.Null)
            return Usage(
                int_at(u, "input_tokens"),
                int_at(u, "cache_read_input_tokens") + int_at(
                    u, "cache_creation_input_tokens"
                ),
                int_at(u, "output_tokens"),
                int_at(ev, "num_turns"),
                ev.get("total_cost_usd").get(
                    JsonValue.Null
                ).as_float().get(0.0),
                "harness"
            )

        return Usage()
