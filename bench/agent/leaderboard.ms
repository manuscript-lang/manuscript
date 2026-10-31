# Collect Harbor trials into results/trials-YYYY-MM-DD.jsonl and render results/leaderboard-YYYY-MM-DD.md.
#
#     ms run bench/agent/leaderboard.ms -- collect JOBS_DIR [JOBS_DIR ...]   # write results/trials-YYYY-MM-DD.jsonl
#     ms run bench/agent/leaderboard.ms -- render [trials-file]              # write results/leaderboard-YYYY-MM-DD.md
#
# Run from the repository root. Pass rate counts every trial. Cost, tokens, turns and time average over PASSING
# trials only, so a cheap wrong answer never improves a ranking. Tokens are input (cache reads included) plus
# output. Turns are agent steps in the Harbor trajectory. Ranking: pass rate, then mean cost of passing trials.
import JsonValue, parse from "@std/json.ms"
import access, glob, list, stat, write_file from "@std/fs.ms"
import stdout, stderr from "@std/io.ms"
import arguments from "@std/process.ms"
import parse_timestamp, wall_clock from "@std/time.ms"
import round from "@std/math.ms"
import root from "./core/model.ms"
import dumps, dumps_data from "./lib/pyjson.ms"
import fixed, mean_scaled, pct0 from "./lib/pyfmt.ms"
import must_read, nonblank_lines, read_text, write_text from "./lib/text.ms"

let MIN_RUNS = 3
let CATEGORIES = ["base", "docs", "reads", "build", "writes", "model output"]


# One graded Harbor trial, as a line of `trials-*.jsonl`.
type Trial:
    trial: String
    challenge: String
    category: String
    tier: Int
    language: String
    agent: String?
    model: String?
    pass: Bool
    errored: Bool
    cases_passed: Int?
    cases_total: Int?
    first_build_ok: Bool?
    code_tokens: Int?
    builds: Int?
    tokens_in: Int
    tokens_cached: Int
    tokens_out: Int
    cost_usd: Float
    turns: Int
    wall_s: Float
    input_by_source: JsonValue
    started: String

fn lang_name(id: String) String:
    if id == "ts": return "TypeScript"
    if id == "go": return "Go"
    if id == "rust": return "Rust"
    if id == "ms": return "Manuscript"
    return id.clone()

fn today() String:
    return wall_clock().now().format("YYYY-MM-DD", "Local").get("")

fn trials_file() String: "{root()}/results/trials-{today()}.jsonl"

fn text_at(doc: JsonValue, key: String) String:
    return doc.get(key).get(JsonValue.Null).as_string().get("")

fn seconds_of(text: String) Float:
    let t = parse_timestamp(text).get()
    return t.unix_seconds().to_float() + t.nanoseconds().to_float() / 1000000000.0

# Which kind of content a step's tool results add to the context.
fn categorize(step: JsonValue) String:
    let calls = step.get("tool_calls").get(JsonValue.Null).as_list().get([])
    let text = calls.map(fn c: dumps(c.get("arguments").get(JsonValue.ObjectValue(Map[String, JsonValue]())), 0)).join(" ")
    let names = calls.map(fn c: text_at(c, "function_name"))
    if names.any(fn n: n == "Write" or n == "Edit" or n == "MultiEdit" or n == "NotebookEdit"): return "writes"
    if text.contains("docs"): return "docs"
    let build_marks = ["check.sh", "ms build", "ms check", "ms run", "cargo ", "go build", "node "]
    if build_marks.any(fn k: text.contains(k)): return "build"
    return "reads"

fn metric(step: JsonValue, key: String) Float:
    return step.get("metrics").get(JsonValue.Null).get(key).get(JsonValue.Null).as_float().get(0.0)

# Attributes input tokens (cache reads included) to the source of the context they carry.
#
# Each step re-sends the whole context. We track how the context grew since the previous step, credit the growth to
# the previous step's tool category (and its completion tokens to "model output"), and split every step's prompt
# tokens by the running composition. The total equals the sum of prompt tokens over agent steps.
fn breakdown(steps: List[JsonValue]) List[Float]:
    var comp = CATEGORIES.map(fn _c: 0.0)
    var out = CATEGORIES.map(fn _c: 0.0)
    var prev_prompt = 0.0
    var prev: JsonValue? = none
    for st in steps:
        if text_at(st, "source") != "agent" or st.get("metrics").is_none(): continue

        let prompt = metric(st, "prompt_tokens")
        if let before = prev:
            let done = metric(before, "completion_tokens")
            comp[5] = comp[5] + done
            let at = CATEGORIES.index_of(categorize(before)).get(0)
            let grown = prompt - prev_prompt - done
            comp[at] = comp[at] + (if grown > 0.0: grown else: 0.0)
        else:
            comp[0] = prompt
        var total = comp.sum()
        if total == 0.0: total = 1.0
        for i in 0..CATEGORIES.length(): out[i] = out[i] + prompt * comp[i] / total
        prev_prompt = prompt
        prev = st.clone()
    return out

fn read_trial(dir: String) Trial?:
    if not access("{dir}/result.json", 0).is_ok(): return none

    let r = parse(must_read("{dir}/result.json")).get(JsonValue.Null)
    let task = r.get("task_name")
    if task.is_none(): return none

    let name = task.get(JsonValue.Null).as_string().get("").split("/").last().get("")
    let cut = name.last_index_of("-").get(0)
    let cid = name.slice(0, cut).get("")
    let lang = name.slice(cut + 1, name.length()).get("")
    let meta_file = "{root()}/challenges/{cid}/challenge.json"
    if not access(meta_file, 0).is_ok(): return none

    let meta = parse(must_read(meta_file)).get(JsonValue.Null)
    let ar = r.get("agent_result").get(JsonValue.Null)
    let reward = r.get("verifier_result").get(JsonValue.Null).get("rewards").get(JsonValue.Null).get("reward")
    var detail = JsonValue.Null
    if access("{dir}/verifier/detail.json", 0).is_ok(): detail = parse(must_read("{dir}/verifier/detail.json")).get(JsonValue.Null)
    var turns = 0
    var sources = Map[String, JsonValue]()
    if access("{dir}/agent/trajectory.json", 0).is_ok():
        let steps = parse(must_read("{dir}/agent/trajectory.json")).get(JsonValue.Null).get("steps").get(JsonValue.Null).as_list().get([])
        turns = steps.count(fn s: text_at(s, "source") == "agent")
        let split = breakdown(steps)
        let cats = CATEGORIES
        for n in 0..cats.length():
            sources.add(cats[n].clone(), JsonValue.NumberValue("{round(split[n]).truncate_to_int().get(0)}"))
    let ex = r.get("agent_execution").get(JsonValue.Null)
    var wall = 0.0
    if ex.get("started_at").is_some() and ex.get("finished_at").is_some():
        wall = seconds_of(text_at(ex, "finished_at")) - seconds_of(text_at(ex, "started_at"))
    let agent_cfg = r.get("config").get(JsonValue.Null).get("agent").get(JsonValue.Null)
    let score = reward.get(JsonValue.Null).as_float()
    let passed = score.get(0.0) == 1.0
    return Trial(
        text_at(r, "trial_name"), cid.clone(), text_at(meta, "category"), meta.get("tier").get(JsonValue.Null).as_int().get(0),
        lang.clone(), agent_cfg.get("name").get(JsonValue.Null).as_string(), agent_cfg.get("model_name").get(JsonValue.Null).as_string(),
        passed, score.is_none(), detail.get("passed").get(JsonValue.Null).as_int(), detail.get("total").get(JsonValue.Null).as_int(),
        detail.get("first_build_ok").get(JsonValue.Null).as_bool(), detail.get("code_tokens").get(JsonValue.Null).as_int(),
        detail.get("builds").get(JsonValue.Null).as_int(), ar.get("n_input_tokens").get(JsonValue.Null).as_int().get(0),
        ar.get("n_cache_tokens").get(JsonValue.Null).as_int().get(0), ar.get("n_output_tokens").get(JsonValue.Null).as_int().get(0),
        ar.get("cost_usd").get(JsonValue.Null).as_float().get(0.0), turns, round(wall * 10.0) / 10.0,
        JsonValue.ObjectValue(sources), r.get("started_at").get(JsonValue.Null).as_string().get("")
    )

fn read_trials(path: String) List[Trial]:
    var rows = List[Trial]()
    for line in nonblank_lines(read_text(path)):
        rows.append(parse[Trial](line).get())
    return rows

fn collect(dirs: List[String]) Int:
    var rows = read_trials(trials_file())
    for jobs in dirs:
        for path in glob(jobs, "**/*__*", none).get([]):
            let dir = "{jobs}/{path}"
            let leaf = path.split("/").last().get("")
            let is_dir = stat(dir, true).to_optional().map(fn s: s.directory).get(false)
            if is_dir and leaf.split("__").length() == 2:
                if let t = read_trial(dir):
                    rows = rows.filter(fn old: old.trial != t.trial)
                    rows.append(t)
    # A resumed job reruns trials; keep one (the latest) per challenge, language, agent and model.
    var latest = List[Trial]()
    for t in rows.sorted(fn a, b: a.started.compare(b.started)):
        latest = latest.filter(fn o: not (o.challenge == t.challenge and o.language == t.language and o.agent == t.agent and o.model == t.model))
        latest.append(t.clone())
    let kept = latest.sorted(fn a, b: a.trial.compare(b.trial))
    write_text(trials_file(), kept.map(fn t: dumps_data(t, 0) + "\n").join(""))
    stdout().write("{kept.length()} trials in {trials_file()}\n").get()
    return 0

# Aggregates of one group of trials; passing trials only for the averages.
type Agg:
    n: Int
    pass: Float
    fb: Float
    tokens: Float?
    turns: Float?
    wall: Float?
    cost: Float?
    code: Float?

fn mean_of(values: List[Float]) Float?:
    if values.is_empty(): return none

    return values.sum() / values.length().to_float()

fn mean_scaled_opt(values: List[Float], scale: Float) Float?:
    if values.is_empty(): return none

    return mean_scaled(values, scale)

fn agg(rs: List[Trial]) Agg:
    let ok = rs.filter(fn r: r.pass)
    let coded = ok.filter(fn r: r.code_tokens.is_some())
    return Agg(
        rs.length(), ok.length().to_float() / rs.length().to_float(),
        rs.count(fn r: r.first_build_ok.get(false)).to_float() / rs.length().to_float(),
        mean_of(ok.map(fn r: (r.tokens_in + r.tokens_out).to_float())), mean_of(ok.map(fn r: r.turns.to_float())),
        mean_scaled_opt(ok.map(fn r: r.wall_s), 10.0), mean_of(ok.map(fn r: r.cost_usd)), mean_of(coded.map(fn r: r.code_tokens.get(0).to_float()))
    )

fn fmt(v: Float?, kind: String) String:
    if v.is_none(): return if kind == "n0": "n/a" else: "-"

    let x = v.get(0.0)
    if kind == "pct": return pct0(x)
    if kind == "tok": return fixed(x / 1000.0, 0) + "k"
    if kind == "n": return fixed(x, 1)
    if kind == "usd": return "$" + fixed(x, 3)
    return fixed(x, 0)

type Row:
    key: String
    stats: Agg

fn table(title: String, rs: List[Trial], key: fn(Trial) String, label: String) String:
    var lines = ["### {title}", ""]
    lines.append("| rank | {label} | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |")
    lines.append("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    let keys = rs.map(key).distinct()
    var rows = keys.map(fn k: Row(k.clone(), agg(rs.filter(fn t: key(t) == k))))
    rows = rows.entries().sorted(fn a, b: order(a.value, b.value, a.index, b.index)).map(fn e: e.value.clone())
    for i in 0..rows.length():
        let a = rows[i].stats
        let prov = if a.n < MIN_RUNS * 5: " (provisional)" else: ""
        lines.append(
            "| {i + 1} | {rows[i].key}{prov} | {a.n} | {fmt(a.pass, "pct")} | {fmt(a.fb, "pct")} | {fmt(a.tokens, "tok")} | {fmt(a.code, "n0")} | {fmt(a.turns, "n")} | {fmt(a.wall, "n")} | {fmt(a.cost, "usd")} |"
        )
    return lines.join("\n") + "\n"

# Higher pass rate first, then lower cost; trials without a passing run sort last, then input order.
fn order(a: Row, b: Row, ai: Int, bi: Int) Int:
    if a.stats.pass != b.stats.pass: return if a.stats.pass > b.stats.pass: -1 else: 1

    let ac = a.stats.cost.get(1000000000.0)
    let bc = b.stats.cost.get(1000000000.0)
    if ac != bc: return if ac < bc: -1 else: 1

    return ai - bi

fn source_value(t: Trial, c: String) Float:
    return t.input_by_source.get(c).get(JsonValue.Null).as_float().get(0.0)

# Where input tokens go, per language, averaged over passing trials.
fn source_table(rows: List[Trial]) String:
    var lines = ["### Where the input tokens go (passing trials, mean per trial)", ""]
    lines.append("Input tokens include cache reads. `base` is the system prompt plus the task, re-sent on every step, so it scales with turns; `docs` is the Manuscript docs bundle when the agent reads it;")
    lines.append("`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls.")
    lines.append("")
    lines.append("| language | input | output | {CATEGORIES.join(" | ")} |")
    lines.append("|---|---:|---:|" + CATEGORIES.map(fn _c: "---:|").join(""))
    for lang in ["ts", "go", "rust", "ms"]:
        let ok = rows.filter(fn t: t.language == lang and t.pass and t.input_by_source != JsonValue.ObjectValue(Map[String, JsonValue]()))
        if ok.is_empty(): continue

        let mean_in = ok.map(fn t: t.tokens_in.to_float()).sum() / ok.length().to_float()
        let out = ok.map(fn t: t.tokens_out.to_float()).sum() / ok.length().to_float()
        let cells = CATEGORIES.map(fn c: fixed(ok.map(fn t: source_value(t, c)).sum() / ok.length().to_float() / 1000.0, 0) + "k")
        lines.append("| {lang_name(lang)} | {fixed(mean_in / 1000.0, 0)}k | {fixed(out / 1000.0, 1)}k | {cells.join(" | ")} |")
    return lines.join("\n") + "\n"

fn render(src_arg: String?) Int:
    var src = src_arg.get("")
    if src == "":
        let found = glob("{root()}/results", "trials-*.jsonl", none).get([])
        src = "{root()}/results/{found.sorted().last().get("")}"
    let board = src.replace("trials-", "leaderboard-").replace(".jsonl", ".md")
    let trials = read_trials(src)
    let clean = trials.filter(fn t: not t.errored)
    var out = ["# agent-bench leaderboard", ""]
    out.append("{trials.length()} trials ({trials.length() - clean.length()} errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. `agent tokens` is what the agent consumed (input including cache reads, plus output). `solution size (tokens)` is the number of lexical tokens (identifiers, literals, punctuation; comments excluded) in the final source it wrote, mean over passing trials; `n/a` means the run predates the measurement. Ranked by pass rate, then cost.")
    out.append("")
    out.append(table("Languages (all models)", clean, fn t: lang_name(t.language), "language"))
    out.append(table("Models (all languages)", clean, fn t: "{t.agent.get("None")} / {t.model.get("None")}", "agent / model"))
    out.append(table("Model x language", clean, fn t: "{t.model.get("None")} / {lang_name(t.language)}", "model / language"))
    out.append(source_table(clean))
    for cat in clean.map(fn t: t.category.clone()).distinct().sorted():
        out.append(table("Category: {cat}", clean.filter(fn t: t.category == cat), fn t: lang_name(t.language), "language"))
    for tier in clean.map(fn t: t.tier).distinct().sorted():
        out.append(table("Tier {tier}", clean.filter(fn t: t.tier == tier), fn t: lang_name(t.language), "language"))
    write_text(board, out.join("\n"))
    stdout().write("wrote {board}\n").get()
    return 0

export fn main() Int:
    let args = arguments()
    if args.length() >= 2 and args[0] == "collect": return collect(args.slice(1, args.length()).get([]))
    if args.length() == 1 and args[0] == "render": return render(none)
    if args.length() == 2 and args[0] == "render": return render(args[1].clone())

    stderr().write("usage: leaderboard.ms collect JOBS_DIR [JOBS_DIR ...] | render [trials-file]\n").get()
    return 2
