// Collect Harbor trials into results/trials-YYYY-MM-DD.jsonl and render
// results/leaderboard-YYYY-MM-DD.md.
//
//     ms run bench/agent/leaderboard.ms -- collect JOBS_DIR [JOBS_DIR ...]   # write results/trials-YYYY-MM-DD.jsonl
//     ms run bench/agent/leaderboard.ms -- render [trials-file]              # write results/leaderboard-YYYY-MM-DD.md
//
// Run from the repository root. Pass rate counts every trial. Cost, tokens, turns and
// time average over PASSING trials only, so a cheap wrong answer never improves a
// ranking. Tokens are input (cache reads included) plus output. Turns are agent steps
// in the Harbor trajectory. Ranking: pass rate, then mean cost of passing trials.
import (
	JsonValue, parse from "@std/data/json.ms",
	stderr from "@std/io/io.ms",
	round from "@std/math/math.ms",
	arguments from "@std/os/env.ms",
	GlobOptions, access, glob, stat from "@std/os/fs.ms",
	now, parse_timestamp from "@std/time.ms",

	root from "./core/model.ms",
	fixed, mean_scaled, pct0 from "./lib/pyfmt.ms",
	dumps, dumps_data from "./lib/pyjson.ms",
	must_read, nonblank_lines, read_text, write_text from "./lib/text.ms",
)

MIN_RUNS := 3
CATEGORIES := ["base", "docs", "reads", "build", "writes", "model output"]

// One graded Harbor trial, as a line of `trials-*.jsonl`.
type Trial {
	trial String
	challenge String
	category String
	tier Int
	language String
	pass Bool
	errored Bool
	tokens_in Int
	tokens_cached Int
	tokens_out Int
	cost_usd Float
	turns Int
	wall_s Float
	input_by_source JsonValue
	started String
	agent String?
	model String?
	cases_passed Int?
	cases_total Int?
	first_build_ok Bool?
	code_tokens Int?
	builds Int?
}

fn lang_name(id String) String {
	if id == "ts" { return "TypeScript" }
	if id == "go" { return "Go" }
	if id == "rust" { return "Rust" }
	if id == "ms" { return "Manuscript" }

	return id.clone()
}

fn today() String {
	return now().format("YYYY-MM-DD", "Local").get_or("")
}

fn trials_file() String => f"{root()}/results/trials-{today()}.jsonl"

fn text_at(doc JsonValue, key String) String {
	return (doc.get(key) or JsonValue.Null).as_string() or ""
}

fn seconds_of(text String) Float {
	t := parse_timestamp(text).get()
	return t.unix_seconds().to_float() + t.nanoseconds().to_float() / 1000000000.0
}

// Which kind of content a step's tool results add to the context.
fn categorize(step JsonValue) String {
	calls := (step.get("tool_calls") or JsonValue.Null).as_list() or []
	text := calls.map(
		c => dumps(
			c.get("arguments") or JsonValue.ObjectValue(
				Map[String, JsonValue]()
			),
			0,
		)
	).join(" ")
	names := calls.map(c => text_at(c, "function_name"))
	if names.any(
		n => (
			n == "Write"
			or n == "Edit"
			or n == "MultiEdit"
			or n == "NotebookEdit"
		)
	) { return "writes" }
	if text.contains("docs") { return "docs" }

	build_marks := [
		"check.sh", "ms build", "ms check", "ms run", "cargo ", "go build", "node "
	]
	if build_marks.any(k => text.contains(k)) { return "build" }

	return "reads"
}

fn metric(step JsonValue, key String) Float {
	return (
		(
			(step.get("metrics") or JsonValue.Null).get(key)
			or JsonValue.Null
		).as_float()
		or 0.0
	)
}

// Attributes input tokens (cache reads included) to the source of the context they
// carry.
//
// Each step re-sends the whole context. We track how the context grew since the
// previous step, credit the growth to the previous step's tool category (and its
// completion tokens to "model output"), and split every step's prompt tokens by the
// running composition. The total equals the sum of prompt tokens over agent steps.
fn breakdown(steps List[JsonValue]) List[Float] {
	var comp = CATEGORIES.map(_c => 0.0)
	var out = CATEGORIES.map(_c => 0.0)
	var prev_prompt = 0.0
	var prev JsonValue? = null

	for st in steps {
		if text_at(st, "source") != "agent" or (st.get("metrics") == null) { continue }

		prompt := metric(st, "prompt_tokens")
		before := prev

		if before != null {
			done := metric(before, "completion_tokens")
			comp[5] += done

			at := CATEGORIES.index_of(categorize(before)) or 0
			grown := prompt - prev_prompt - done
			comp[at] = comp[at] + (if grown > 0.0 { grown } else { 0.0 })
		} else {
			comp[0] = prompt
		}

		var total = comp.sum()
		if total == 0.0 { total = 1.0 }
		for i in 0..CATEGORIES.length() { out[i] += prompt * comp[i] / total }
		prev_prompt = prompt
		prev = st.clone()
	}

	return out
}

fn read_trial(dir String) Trial? {
	if not access(f"{dir}/result.json", 0).is_ok() { return null }

	r := parse(must_read(f"{dir}/result.json")).get_or(JsonValue.Null)
	task := r.get("task_name")
	if task == null { return null }

	name := ((task).as_string() or "").split("/").last() or ""
	cut := name.last_index_of("-") or 0
	cid := name.slice(0, cut)
	lang := name.slice(cut + 1, name.length())
	meta_file := f"{root()}/challenges/{cid}/challenge.json"
	if not access(meta_file, 0).is_ok() { return null }

	meta := parse(must_read(meta_file)).get_or(JsonValue.Null)
	ar := r.get("agent_result") or JsonValue.Null
	reward := (
		(r.get("verifier_result") or JsonValue.Null).get("rewards")
		or JsonValue.Null
	).get("reward")
	var detail = JsonValue.Null
	if access(f"{dir}/verifier/detail.json", 0).is_ok() {
		detail = parse(must_read(f"{dir}/verifier/detail.json")).get_or(JsonValue.Null)
	}

	var turns = 0
	var sources = Map[String, JsonValue]()

	if access(f"{dir}/agent/trajectory.json", 0).is_ok() {
		steps := (
			(
				parse(must_read(f"{dir}/agent/trajectory.json")).get_or(
					JsonValue.Null
				).get("steps")
				or JsonValue.Null
			).as_list()
			or []
		)
		turns = steps.count(s => text_at(s, "source") == "agent")

		split := breakdown(steps)
		cats := CATEGORIES
		for n in 0..cats.length() {
			sources.add(
				cats[n].clone(),
				JsonValue.NumberValue(
					f"{(round(split[n]).truncate_to_int() or 0)}"
				),
			)
		}
	}

	ex := r.get("agent_execution") or JsonValue.Null
	var wall = 0.0
	if (ex.get("started_at") != null) and (ex.get("finished_at") != null) {
		wall = (
			seconds_of(text_at(ex, "finished_at"))
			- seconds_of(text_at(ex, "started_at"))
		)
	}

	agent_cfg := (r.get("config") or JsonValue.Null).get("agent") or JsonValue.Null
	score := (reward or JsonValue.Null).as_float()
	passed := (score or 0.0) == 1.0
	return Trial(
		trial: text_at(r, "trial_name"),
		challenge: cid.clone(),
		category: text_at(meta, "category"),
		tier: (meta.get("tier") or JsonValue.Null).as_int() or 0,
		language: lang.clone(),
		agent: (agent_cfg.get("name") or JsonValue.Null).as_string(),
		model: (agent_cfg.get("model_name") or JsonValue.Null).as_string(),
		pass: passed,
		errored: score == null,
		cases_passed: (detail.get("passed") or JsonValue.Null).as_int(),
		cases_total: (detail.get("total") or JsonValue.Null).as_int(),
		first_build_ok: (
			detail.get("first_build_ok")
			or JsonValue.Null
		).as_bool(),
		code_tokens: (detail.get("code_tokens") or JsonValue.Null).as_int(),
		builds: (detail.get("builds") or JsonValue.Null).as_int(),
		tokens_in: (ar.get("n_input_tokens") or JsonValue.Null).as_int() or 0,
		tokens_cached: (
			ar.get("n_cache_tokens")
			or JsonValue.Null
		).as_int() or 0,
		tokens_out: (ar.get("n_output_tokens") or JsonValue.Null).as_int() or 0,
		cost_usd: (ar.get("cost_usd") or JsonValue.Null).as_float() or 0.0,
		turns: turns,
		wall_s: round(wall * 10.0) / 10.0,
		input_by_source: JsonValue.ObjectValue(sources),
		started: (r.get("started_at") or JsonValue.Null).as_string() or "",
	)
}

fn read_trials(path String) List[Trial] {
	var rows = List[Trial]()
	for line in nonblank_lines(read_text(path)) {
		rows.append(parse[Trial](line).get())
	}
	return rows
}

fn collect(dirs List[String]) Int {
	var rows = read_trials(trials_file())

	for jobs in dirs {
		for entry in glob(jobs, GlobOptions(patterns: ["**/*__*"])).get_or([]) {
			path := entry.path.clone()
			dir := f"{jobs}/{path}"
			leaf := path.split("/").last() or ""
			info := stat(dir).to_optional()
			is_dir := info != null and info.is_directory()

			if is_dir and leaf.split("__").length() == 2 {
				t := read_trial(dir)

				if t != null {
					rows = rows.filter(old => old.trial != t.trial)
					rows.append(t)
				}
			}
		}
	}

	// A resumed job reruns trials; keep one (the latest) per challenge, language, agent
	// and model.
	var latest = List[Trial]()

	for t in rows.sorted((a, b) => a.started.compare(b.started)) {
		latest = latest.filter(
			o => not (
				o.challenge == t.challenge
				and o.language == t.language
				and o.agent == t.agent
				and o.model == t.model
			)
		)
		latest.append(t.clone())
	}

	kept := latest.sorted((a, b) => a.trial.compare(b.trial))
	write_text(trials_file(), kept.map(t => dumps_data(t, 0) + "\n").join(""))
	print(f"{kept.length()} trials in {trials_file()}")
	return 0
}

// Aggregates of one group of trials; passing trials only for the averages.
type Agg {
	n Int
	pass Float
	fb Float
	tokens Float?
	turns Float?
	wall Float?
	cost Float?
	code Float?
}

fn mean_of(values List[Float]) Float? {
	if values.is_empty() { return null }
	return values.sum() / values.length().to_float()
}

fn mean_scaled_opt(values List[Float], scale Float) Float? {
	if values.is_empty() { return null }
	return mean_scaled(values, scale)
}

fn agg(rs List[Trial]) Agg {
	ok := rs.filter(r => r.pass)
	coded := ok.filter(r => r.code_tokens != null)
	return Agg(
		rs.length(),
		ok.length().to_float() / rs.length().to_float(),
		rs.count(
			r => r.first_build_ok or (false)
		).to_float() / rs.length().to_float(),
		mean_of(ok.map(r => (r.tokens_in + r.tokens_out).to_float())),
		mean_of(ok.map(r => (r.turns.to_float()))),
		mean_scaled_opt(ok.map(r => r.wall_s), 10.0),
		mean_of(ok.map(r => r.cost_usd)),
		mean_of(coded.map(r => ((r.code_tokens or 0).to_float()))),
	)
}

fn fmt(kind String, v Float?) String {
	if v == null { return if kind == "n0" { "n/a" } else { "-" } }

	x := v
	if kind == "pct" { return pct0(x) }
	if kind == "tok" { return fixed(x / 1000.0, 0) + "k" }
	if kind == "n" { return fixed(x, 1) }
	if kind == "usd" { return "$" + fixed(x, 3) }

	return fixed(x, 0)
}

type Row {
	key String
	stats Agg
}

fn table(title String, rs List[Trial], key fn(Trial) String, label String) String {
	var lines = [f"### {title}", ""]
	lines.append(
		f"| rank | {label} | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |"
	)
	lines.append("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")

	keys := rs.map(key).distinct()
	var rows = keys.map(k => Row(k.clone(), agg(rs.filter(t => key(t) == k))))
	rows = rows.entries().sorted(
		(a, b) => order(a.value, b.value, a.index, b.index)
	).map(e => (e.value.clone()))

	for i in 0..rows.length() {
		a := rows[i].stats
		prov := if a.n < MIN_RUNS * 5 { " (provisional)" } else { "" }
		lines.append(
			f"| {i + 1} | {rows[i].key}{prov} | {a.n} | {fmt("pct", a.pass)} | {fmt("pct", a.fb)} | {fmt("tok", a.tokens)} | {fmt("n0", a.code)} | {fmt("n", a.turns)} | {fmt("n", a.wall)} | {fmt("usd", a.cost)} |"
		)
	}

	return lines.join("\n") + "\n"
}

// Higher pass rate first, then lower cost; trials without a passing run sort last, then
// input order.
fn order(a Row, b Row, ai Int, bi Int) Int {
	if a.stats.pass != b.stats.pass { return if a.stats.pass > b.stats.pass { - 1 } else { 1 } }

	ac := a.stats.cost or 1000000000.0
	bc := b.stats.cost or 1000000000.0
	if ac != bc { return if ac < bc { - 1 } else { 1 } }

	return ai - bi
}

fn source_value(t Trial, c String) Float {
	return (t.input_by_source.get(c) or JsonValue.Null).as_float() or 0.0
}

// Where input tokens go, per language, averaged over passing trials.
fn source_table(rows List[Trial]) String {
	var lines = ["### Where the input tokens go (passing trials, mean per trial)", ""]
	lines.append(
		"Input tokens include cache reads. `base` is the system prompt plus the task, re-sent on every step, so it scales with turns; `docs` is the Manuscript docs bundle when the agent reads it;"
	)
	lines.append(
		"`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls."
	)
	lines.append("")
	lines.append(f"| language | input | output | {CATEGORIES.join(" | ")} |")
	lines.append("|---|---:|---:|" + CATEGORIES.map(_c => "---:|").join(""))

	for lang in ["ts", "go", "rust", "ms"] {
		ok := rows.filter(
			t => (
				t.language == lang
				and t.pass
				and t.input_by_source != JsonValue.ObjectValue(
					Map[String, JsonValue]()
				)
			)
		)
		if ok.is_empty() { continue }

		mean_in := (ok.map(t => t.tokens_in.to_float()).sum() / ok.length().to_float())
		out := ok.map(t => t.tokens_out.to_float()).sum() / ok.length().to_float()
		cells := CATEGORIES.map(
			c => (
				fixed(
					ok.map(
						t => source_value(t, c)
					).sum() / ok.length().to_float() / 1000.0,
					0,
				)
				+ "k"
			)
		)
		lines.append(
			f"| {lang_name(lang)} | {fixed(mean_in / 1000.0, 0)}k | {fixed(out / 1000.0, 1)}k | {cells.join(" | ")} |"
		)
	}

	return lines.join("\n") + "\n"
}

fn render(src_arg String?) Int {
	var src = src_arg.clone() or ""

	if src == "" {
		found := glob(f"{root()}/results", GlobOptions(patterns: ["trials-*.jsonl"])).get_or(
			[]
		)
		names := found.map(e => e.path.clone())
		src = f"{root()}/results/{(names.sorted().last() or "")}"
	}

	board := src.replace("trials-", "leaderboard-").replace(".jsonl", ".md")
	trials := read_trials(src)
	clean := trials.filter(t => not t.errored)
	var out = ["# agent-bench leaderboard", ""]
	out.append(
		f"{trials.length()} trials ({trials.length() - clean.length()} errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. `agent tokens` is what the agent consumed (input including cache reads, plus output). `solution size (tokens)` is the number of lexical tokens (identifiers, literals, punctuation; comments excluded) in the final source it wrote, mean over passing trials; `n/a` means the run predates the measurement. Ranked by pass rate, then cost."
	)
	out.append("")
	out.append(
		table(
			"Languages (all models)",
			clean,
			t => lang_name(t.language),
			"language",
		)
	)
	out.append(
		table(
			"Models (all languages)",
			clean,
			t => f"{(t.agent or "None")} / {(t.model or "None")}",
			"agent / model",
		)
	)
	out.append(
		table(
			"Model x language",
			clean,
			t => f"{(t.model or "None")} / {lang_name(t.language)}",
			"model / language",
		)
	)
	out.append(source_table(clean))
	for cat in clean.map(t => t.category.clone()).distinct().sorted() {
		out.append(
			table(
				f"Category: {cat}",
				clean.filter(t => t.category == cat),
				t => lang_name(t.language),
				"language",
			)
		)
	}
	for tier in clean.map(t => t.tier).distinct().sorted() {
		out.append(
			table(
				f"Tier {tier}",
				clean.filter(t => t.tier == tier),
				t => lang_name(t.language),
				"language",
			)
		)
	}
	write_text(board, out.join("\n"))
	print(f"wrote {board}")
	return 0
}

fn main() Int {
	args := arguments()
	if args.length() >= 2 and args[0] == "collect" {
		return collect(args.slice(1, args.length()).get_or([]))
	}
	if args.length() == 1 and args[0] == "render" { return render(null) }
	if args.length() == 2 and args[0] == "render" { return render(args[1].clone()) }

	(
		stderr()
		.write(
			"usage: leaderboard.ms collect JOBS_DIR [JOBS_DIR ...] | render [trials-file]\n"
		)
		.get()
	)
	return 2
}
