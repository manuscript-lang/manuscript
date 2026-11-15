// Summarize benchmark runs as Markdown tables with 95% confidence intervals.
//
// Pass and first-build rates cover every run (Wilson intervals). Tokens, turns, time
// and cost average over PASSING runs only, so a cheap wrong answer never improves a
// language's numbers (mean with a normal-approximation interval). The last tables rank
// the diagnostic codes agents hit in failed builds. Usage (from the repository root):
// ms run bench/agent/report.ms [-- path/to/runs.jsonl ...]
import (
	parse from "@std/data/json.ms",
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",

	root from "./core/model.ms",
	fmt_g, mean_scaled, pct0 from "./lib/pyfmt.ms",
	Interval, mean_ci, wilson from "./lib/stats.ms",
	nonblank_lines, read_text from "./lib/text.ms",
)

type Usage:
	tokens_in: Int = 0
	tokens_cached: Int = 0
	tokens_out: Int = 0
	turns: Int = 0
	cost_usd: Float = 0.0

type Run:
	challenge: String
	harness: String
	model: String = ""
	language: String
	category: String
	tier: Int
	usage: Usage
	wall_s: Float
	timed_out: Bool = false
	builds: Int = 0
	first_build_ok: Bool
	build_codes: List[String] = []
	pass: Bool

type CodeStat:
	code: String
	count: Int

fn rate(ok: Int, n: Int) String:
	w := wilson(ok, n)
	return "{pct0(w.mid)} ({pct0(w.low)}-{pct0(w.high)})"

fn mean_text(values: List[Float], digits: Int) String:
	if values.is_empty(): return "-"

	m := mean_ci(values)
	return "{fmt_g(m.mid, digits)} ±{fmt_g(m.high - m.mid, 2)}"

fn tokens_of(r: Run) Float:
	return (r.usage.tokens_in + r.usage.tokens_cached + r.usage.tokens_out).to_float()

fn table(runs: List[Run], title: String, key: fn(Run) String) String:
	var out = "\n### {title}\n\n"
	out += "| group | runs | pass (95% CI) | first build ok (95% CI) | tokens (in+out+cache) | turns | wall s | cost $ |\n"
	out += "|---|---:|---:|---:|---:|---:|---:|---:|\n"

	for k in runs.map(key).distinct().sorted():
		rs := runs.filter(fn r: key(r) == k)
		ok := rs.filter(fn r: r.pass)
		n := rs.length()
		first_ok := rs.filter(fn r: r.first_build_ok).length()
		out += "| {k} | {n} | {rate(ok.length(), n)} | {rate(first_ok, n)} "
		out += "| {mean_text(ok.map(tokens_of), 3)} | {mean_text(ok.map(fn r: r.usage.turns.to_float()), 3)} "
		out += "| {mean_text(ok.map(fn r: r.wall_s), 3)} | {mean_text(ok.map(fn r: r.usage.cost_usd), 3)} |\n"

	return out

// One row per challenge, one column per language: passing trials out of all trials.
fn matrix(runs: List[Run]) String:
	langs := runs.map(fn r: r.language.clone()).distinct().sorted()
	var out = "\n### Passing trials per challenge\n\n| challenge | {langs.join(" | ")} |\n"
	out += "|---|{langs.map(fn l: "---:").join("|")}|\n"

	for c in runs.map(fn r: r.challenge.clone()).distinct().sorted():
		out += "| {c} "

		for l in langs:
			cell := runs.filter(fn r: r.challenge == c and r.language == l)
			out += "| {cell.filter(fn r: r.pass).length()}/{cell.length()} "

		out += "|\n"

	return out

// Diagnostic codes in failed builds, most frequent first. "Runs" counts runs that hit
// the code at least once; "extra turns" is those runs' mean turns minus the mean turns
// of runs whose first build succeeded, a rough price of the code.
fn codes_table(runs: List[Run], lang: String) String:
	mine := runs.filter(fn r: r.language == lang)
	clean := mine.filter(fn r: r.first_build_ok).map(fn r: r.usage.turns.to_float())
	base := if clean.is_empty(): 0.0 else: mean_ci(clean).mid
	failing := mine.filter(fn r: not r.first_build_ok).length()
	var out = "\n### {lang}: diagnostic codes in failed builds\n\n"
	out += "{failing} of {mine.length()} runs failed their first build. "
	out += "Baseline: {fmt_g(base, 3)} turns when it succeeds.\n\n"
	out += "| code | occurrences | runs | extra turns per run |\n|---|---:|---:|---:|\n"

	all := mine.flat_map(fn r: r.build_codes.clone())
	stats := all.distinct().map(fn c: CodeStat(c.clone(), all.count(fn x: x == c)))
	ranked := stats.sorted_by_key(fn s: 0 - s.count)

	for entry in ranked.take(15):
		code := entry.code
		hit := mine.filter(fn r: r.build_codes.contains(code))
		turns := mean_ci(hit.map(fn r: r.usage.turns.to_float())).mid
		out += "| {code} | {entry.count} | {hit.length()} | {fmt_g(turns - base, 2)} |\n"

	return out

fn main() Int:
	args := arguments()
	paths := if args.is_empty(): ["{root()}/results/runs.jsonl"] else: args
	var runs = List[Run]()
	for path in paths:
		for line in nonblank_lines(read_text(path)):
			runs.append(parse[Run](line).get())

	if runs.is_empty():
		stderr().write("no runs\n").get()
		return 1

	var text = "{runs.length()} runs from {paths.length()} file(s).\n"
	text += table(
		runs,
		"By model, harness and language",
		fn r: "{r.model} / {r.harness} / {r.language}"
	)
	text += table(runs, "By language and category", fn r: "{r.language} / {r.category}")
	text += table(runs, "By language and tier", fn r: "{r.language} / tier {r.tier}")
	text += matrix(runs)
	for lang in runs.map(fn r: r.language.clone()).distinct().sorted():
		if runs.any(fn r: r.language == lang and not r.build_codes.is_empty()):
			text += codes_table(runs, lang)
	stdout().write(text).get()
	return 0
