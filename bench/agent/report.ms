// Summarize benchmark runs as Markdown tables with 95% confidence intervals.
//
// The pass rate covers every run and the first-build rates every run that built at
// least once (Wilson intervals). Tokens, turns, time and cost average over PASSING runs
// only, so a cheap wrong answer never improves a language's numbers (mean with a
// normal-approximation interval). The last tables rank the diagnostic codes agents hit
// in failed builds. Usage (from the repository root): ms run bench/agent/report.ms [--
// path/to/runs.jsonl ...]
import (
	parse from "@std/data/json.ms",
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	compile from "@std/regex.ms",

	root from "./core/model.ms",
	fmt_g, mean_scaled, pct0 from "./lib/pyfmt.ms",
	Interval, mean_ci, wilson from "./lib/stats.ms",
	nonblank_lines, read_text from "./lib/text.ms",
)

type Usage {
	tokens_in, tokens_cached, tokens_out, turns Int = 0
	cost_usd Float = 0.0
}

type Run {
	challenge, harness, language, category String
	tier Int
	usage Usage
	wall_s Float
	first_build_ok, pass Bool
	model String = ""
	timed_out Bool = false
	builds Int = 0
	first_build_fixed_ok Bool = false
	build_codes List[String] = []
	build_errors List[String] = []
}

type CodeStat {
	code String
	count Int
}

fn rate(ok, n Int) String {
	if n == 0 { return "-" }

	w := wilson(ok, n)
	return f"{pct0(w.mid)} ({pct0(w.low)}-{pct0(w.high)})"
}

fn mean_text(values List[Float], digits Int) String {
	if values.is_empty() { return "-" }

	m := mean_ci(values)
	return f"{fmt_g(m.mid, digits)} ±{fmt_g(m.high - m.mid, 2)}"
}

fn tokens_of(r Run) Float {
	return (r.usage.tokens_in + r.usage.tokens_cached + r.usage.tokens_out).to_float()
}

// Cost to reach a pass is the headline: pass rate, then what a passing run needed
// (builds, turns, tokens, wall time, cost) and what each pass cost including the failed
// runs. The first-build columns come last because they mostly measure how much a model
// already knows the language.
fn table(runs List[Run], title String, key fn(Run) String) String {
	var out = f"\n### {title}\n\n"
	out += "| group | runs | pass (95% CI) | builds per pass | turns per pass | tokens per pass (in+out+cache) | wall s per pass | cost $ per pass | cost $ per pass incl. failed runs | first build ok (95% CI) | first build after `--fix` (95% CI) |\n"
	out += "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"

	for k in runs.map(key).distinct().sorted() {
		rs := runs.filter(r => key(r) == k)
		ok := rs.filter(r => r.pass)
		n := rs.length()

		// Runs whose agent never ran ./check.sh have no first build to count.
		built := rs.filter(r => r.builds > 0)
		first_ok := built.filter(r => r.first_build_ok).length()
		fixed_ok := built.filter(
			r => r.first_build_ok or r.first_build_fixed_ok
		).length()
		spent := rs.map(r => r.usage.cost_usd).sum()
		per_pass := if ok.is_empty() {
			"n/a"
		} else {
			fmt_g(spent / ok.length().to_float(), 3)
		}
		out += f"| {k} | {n} | {rate(ok.length(), n)} | {mean_text(ok.map(r => r.builds.to_float()), 3)} "
		out += f"| {mean_text(ok.map(r => r.usage.turns.to_float()), 3)} | {mean_text(ok.map(tokens_of), 3)} "
		out += f"| {mean_text(ok.map(r => r.wall_s), 3)} | {mean_text(ok.map(r => r.usage.cost_usd), 3)} | {per_pass} "
		out += f"| {rate(first_ok, built.length())} | {rate(fixed_ok, built.length())} |\n"
	}

	return out
}

// One row per challenge, one column per language: passing trials out of all trials.
fn matrix(runs List[Run]) String {
	langs := runs.map(r => r.language.clone()).distinct().sorted()
	var out = f"\n### Passing trials per challenge\n\n| challenge | {langs.join(" | ")} |\n"
	out += f"|---|{langs.map(l => "---:").join("|")}|\n"

	for c in runs.map(r => r.challenge.clone()).distinct().sorted() {
		out += f"| {c} "

		for l in langs {
			cell := runs.filter(r => r.challenge == c and r.language == l)
			out += f"| {cell.filter(r => r.pass).length()}/{cell.length()} "
		}

		out += "|\n"
	}

	return out
}

// Diagnostic codes in failed builds, most frequent first. "Runs" counts runs that hit
// the code at least once; the last two columns are those runs' mean turns and builds,
// to compare with the language's mean over all runs (challenge mix confounds the
// comparison, so read it as a rough price, not a measurement).
fn codes_table(runs List[Run], lang String) String {
	mine := runs.filter(r => r.language == lang)
	overall := mean_ci(mine.map(r => r.usage.turns.to_float())).mid
	overall_builds := mean_ci(mine.map(r => r.builds.to_float())).mid
	failing := mine.filter(r => not r.first_build_ok).length()
	var out = f"\n### {lang}: diagnostic codes in failed builds\n\n"
	out += f"{failing} of {mine.length()} runs failed their first build. "
	out += f"All runs average {fmt_g(overall, 3)} turns and {fmt_g(overall_builds, 3)} builds.\n\n"
	out += "| code | occurrences | runs | turns in those runs | builds in those runs |\n|---|---:|---:|---:|---:|\n"

	all := mine.flat_map(r => r.build_codes.clone())
	stats := all.distinct().map(c => CodeStat(c.clone(), all.count(x => x == c)))
	ranked := stats.sorted_by_key(s => 0 - s.count)

	for entry in ranked.take(15) {
		code := entry.code
		hit := mine.filter(r => r.build_codes.contains(code))
		turns := mean_ci(hit.map(r => r.usage.turns.to_float())).mid
		builds := mean_ci(hit.map(r => r.builds.to_float())).mid
		out += f"| {code} | {entry.count} | {hit.length()} | {fmt_g(turns, 3)} | {fmt_g(builds, 3)} |\n"
	}

	return out
}

fn cut(text String, limit Int) String {
	if text.length() <= limit { return text.clone() }
	return text.slice(0, limit)
}

// The first diagnostic line of failed builds with the location and quoted names
// removed, so equal mistakes group together, most frequent first.
fn errors_table(runs List[Run], lang String) String {
	place := compile("^\\S+:\\d+:\\d+: ").get()
	quoted := compile("'[^']*'").get()
	mine := runs.filter(r => r.language == lang)
	all := mine.flat_map(
		r => r.build_errors.map(
			e => quoted.replace_all(
				place.replace_all(e, "", null).get_or(e.clone()),
				"'X'",
				null,
			).get_or(e)
		)
	)
	stats := all.distinct().map(m => CodeStat(m.clone(), all.count(x => x == m)))
	var out = f"\n### {lang}: most common first error line of failed builds\n\n"
	out += "| message | occurrences |\n|---|---:|\n"
	for entry in stats.sorted_by_key(s => 0 - s.count).take(15) {
		out += f"| {cut(entry.code, 110)} | {entry.count} |\n"
	}
	return out
}

fn main() Int {
	args := arguments()
	paths := if args.is_empty() { [f"{root()}/results/runs.jsonl"] } else { args }
	var runs = List[Run]()
	for path in paths {
		for line in nonblank_lines(read_text(path)) {
			runs.append(parse[Run](line).get())
		}
	}

	if runs.is_empty() {
		stderr().write("no runs\n").get()
		return 1
	}

	var text = f"{runs.length()} runs from {paths.length()} file(s).\n"
	text += table(
		runs,
		"By model, harness and language",
		r => f"{r.model} / {r.harness} / {r.language}",
	)
	text += table(runs, "By language and category", r => f"{r.language} / {r.category}")
	text += table(runs, "By language and tier", r => f"{r.language} / tier {r.tier}")
	text += matrix(runs)

	for lang in runs.map(r => r.language.clone()).distinct().sorted() {
		if runs.any(r => r.language == lang and not r.build_codes.is_empty()) {
			text += codes_table(runs, lang)
		}
		if runs.any(r => r.language == lang and not r.build_errors.is_empty()) {
			text += errors_table(runs, lang)
		}
	}

	stdout().write(text).get()
	return 0
}
