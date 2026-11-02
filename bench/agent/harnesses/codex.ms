import JsonValue from "@std/data/json.ms"
import Harness, Usage, events, int_at from "./harness.ms"

# UNTESTED: written from the documented `codex exec --json` event stream.
export type Codex:
    placeholder: Bool = true

impl Harness for Codex:
    fn name() String: "codex"

    fn command(prompt: String, model: String?, workspace: String) List[String]:
        var cmd = [
            "codex", "exec", "--json", "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check", "-C", workspace.clone()
        ]
        if let m = model: cmd = cmd.concat(["-m", m.clone()])
        return cmd.concat([prompt.clone()])

    # Codex reports no cost; the runner estimates it from pricing.json.
    fn parse(transcript: String) Usage:
        var u = Usage()

        for ev in events(transcript):
            if (
                ev.get("type").get(JsonValue.Null).as_string().get(
                    ""
                ) != "turn.completed"
            ): continue

            let us = ev.get("usage").get(JsonValue.Null)
            let cached = int_at(us, "cached_input_tokens")
            u.tokens_in += int_at(us, "input_tokens") - cached
            u.tokens_cached += cached
            u.tokens_out += int_at(us, "output_tokens")
            u.turns += 1

        return u
