# Harness adapter interface.
#
# A harness drives one coding agent CLI inside a workspace. To add one, implement `Harness` in its own file
# next to this one and register it in `all.ms`.
import write_file from "@std/fs.ms"
import JsonValue, parse from "@std/json.ms"
import round from "@std/math.ms"
import cost_from_tokens from "../core/model.ms"
import run_in from "../lib/text.ms"

export type Usage:
    # Uncached input tokens.
    tokens_in: Int = 0
    # Cache reads (and writes, where the harness reports them together).
    tokens_cached: Int = 0
    tokens_out: Int = 0
    turns: Int = 0
    cost_usd: Float = 0.0
    # `harness`, `estimated` or `none`.
    cost_source: String = "none"

# What one agent run produced.
export type AgentRun:
    usage: Usage
    wall_s: Float
    exit_code: Int
    timed_out: Bool

export interface Harness:
    fn name() String
    # The argv that runs the agent non-interactively in `workspace` and exits when done.
    fn command(prompt: String, model: String?, workspace: String) List[String]
    # Extracts usage from the harness's raw standard output.
    fn parse(transcript: String) Usage

# The JSON event on each line of `transcript` that parses.
export fn events(transcript: String) List[JsonValue]:
    var out = List[JsonValue]()
    for line in transcript.split("\n"):
        if let event = parse(line).to_optional(): out.append(event)
    return out

export fn int_at(doc: JsonValue, key: String) Int:
    if let value = doc.get(key): return value.as_int().get(0)

    return 0

# Runs the agent in `workspace`, saves its output to `transcript` and returns the measured run.
export fn run_agent(
    h: Harness,
    prompt: String,
    model: String?,
    workspace: String,
    timeout_s: Int,
    transcript: String
) AgentRun:
    let argv = h.command(prompt, model, workspace)
    let wrapper = ["-c", "cd \"$0\" && exec \"$@\"", workspace.clone()].concat(argv)
    let ran = run_in("bash", wrapper, timeout_s, "")
    write_file(transcript, ran.out, replace: true).get()

    var usage = h.parse(ran.out)

    if usage.cost_source == "none" and (usage.tokens_in > 0 or usage.tokens_out > 0):
        usage.cost_usd = cost_from_tokens(
            usage.tokens_in, usage.tokens_cached, usage.tokens_out, model.get("default")
        )
        usage.cost_source = "estimated"

    return AgentRun(
        usage, round(ran.seconds * 100.0) / 100.0, ran.code,
        ran.code == 124 and ran.err == "timeout"
    )
