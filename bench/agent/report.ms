# Summarize results/runs.jsonl as Markdown tables.
#
# Pass rate counts every run. Tokens, turns, time and cost average over PASSING runs only,
# so a cheap wrong answer never improves a language's numbers.
# Usage (from the repository root): ms run bench/agent/report.ms [-- path/to/runs.jsonl]
import parse from "@std/json.ms"
import stdout, stderr from "@std/io.ms"
import arguments from "@std/process.ms"
import root from "./core/model.ms"
import fmt_g, mean_scaled, pct0 from "./lib/pyfmt.ms"
import nonblank_lines, read_text from "./lib/text.ms"

type Usage:
    tokens_in: Int = 0
    tokens_cached: Int = 0
    tokens_out: Int = 0
    turns: Int = 0
    cost_usd: Float = 0.0

type Run:
    harness: String
    language: String
    category: String
    tier: Int
    usage: Usage
    wall_s: Float
    first_build_ok: Bool
    pass: Bool

fn mean(values: List[Float]) Float: values.sum() / values.length().to_float()

fn average(ok: List[Run], value: fn(Run) Float) String:
    if ok.is_empty(): return "-"

    return fmt_g(mean(ok.map(value)), 3)

fn wall_mean(ok: List[Run]) String:
    if ok.is_empty(): return "-"

    return fmt_g(mean_scaled(ok.map(fn r: r.wall_s), 100.0), 3)

fn table(runs: List[Run], title: String, key: fn(Run) String) String:
    var out = "\n### {title}\n\n"
    out = out + "| group | runs | pass | first build ok | tokens (in+out) | turns | wall s | cost $ |\n"
    out = out + "|---|---:|---:|---:|---:|---:|---:|---:|\n"
    for k in runs.map(key).distinct().sorted():
        let rs = runs.filter(fn r: key(r) == k)
        let ok = rs.filter(fn r: r.pass)
        let n = rs.length().to_float()
        let first_ok = rs.filter(fn r: r.first_build_ok).length().to_float()
        let tokens = average(ok, fn r: (r.usage.tokens_in + r.usage.tokens_cached + r.usage.tokens_out).to_float())
        out = out + "| {k} | {rs.length()} | {pct0(ok.length().to_float() / n)} | {pct0(first_ok / n)} "
        out = out + "| {tokens} | {average(ok, fn r: r.usage.turns.to_float())} | {wall_mean(ok)} "
        out = out + "| {average(ok, fn r: r.usage.cost_usd)} |\n"
    return out

export fn main() Int:
    let args = arguments()
    let path = if args.is_empty(): "{root()}/results/runs.jsonl" else: args[0].clone()
    var runs = List[Run]()
    for line in nonblank_lines(read_text(path)):
        runs.append(parse[Run](line).get())
    if runs.is_empty():
        stderr().write("no runs\n").get()
        return 1

    var text = table(runs, "By harness and language", fn r: "{r.harness} / {r.language}")
    text = text + table(runs, "By language and category", fn r: "{r.language} / {r.category}")
    text = text + table(runs, "By language and tier", fn r: "{r.language} / tier {r.tier}")
    stdout().write(text).get()
    return 0
