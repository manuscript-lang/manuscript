# Agent-effectiveness benchmark runner. See README.md.
# Usage (from the repository root): ms run bench/agent/run.ms -- <list|run|oracle> [options]
import Command, Flag, FlagKind, command from "@std/cli.ms"
import (
    append_file,
    copy_file,
    remove,
    stat,
    temporary_directory,
    create_directory
) from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import arguments from "@std/os/process.ms"
import uuid_v4 from "@std/os/random.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import now from "@std/os/time.ms"
import Challenge, Lang, root, load_challenges, load_languages from "./core/model.ms"
import Grade, grade, make_workspace, read_log from "./core/workspace.ms"
import Harness, AgentRun, Usage, run_agent from "./harnesses/harness.ms"
import find, names from "./harnesses/all.ms"
import dumps_data from "./lib/pyjson.ms"
import bash, read_text from "./lib/text.ms"

# One line of `results/runs.jsonl`.
type RunRecord:
    run_id: String
    ts: Int
    tag: String
    challenge: String
    category: String
    tier: Int
    language: String
    harness: String
    model: String?
    usage: Usage
    wall_s: Float
    exit_code: Int
    timed_out: Bool
    builds: Int
    first_build_ok: Bool
    checks: Int
    examples_pass: Bool
    suspect_peek: Bool
    grade: Grade
    pass: Bool

type Options:
    harness: String = "oracle"
    model: String?
    challenges: String = ""
    languages: String = ""
    repeat: Int = 1
    jobs: Int = 1
    timeout: Int = 900
    keep: Bool = false
    tag: String = ""
    out: String = "{root()}/results/runs.jsonl"

fn split_ids(text: String) List[String]:
    return text.split(",").filter(fn x: not x.is_empty())

# Source size in LLM tokens (tiktoken o200k_base, a proxy for Claude's tokenizer); none without tiktoken.
fn llm_tokens(path: String) Int?:
    let program = "import sys, tiktoken; print(len(tiktoken.get_encoding('o200k_base').encode(open(sys.argv[1], errors='replace').read(), disallowed_special=())))"
    let ran = bash("python3 -c \"{program}\" \"{path}\"", ".", 60, "")
    if ran.code != 0: return none

    return ran.out.trim().parse_int()

fn reference_for(ch: Challenge, lang: Lang) String:
    return "{ch.solution(lang.template)}/{lang.reference()}"

fn run_one(
    ch: Challenge,
    lang: Lang,
    h: Harness,
    model: String?,
    timeout_s: Int,
    keep: Bool,
    out_file: String,
    tag: String
) RunRecord:
    let run_id = uuid_v4().get("").replace("-", "").take(10)
    let base = temporary_directory("agent-bench-").get()
    let ws = "{base}/ws"
    let prompt = make_workspace(ch, lang, ws)
    let transcripts = "{root()}/results/transcripts"
    create_directory(transcripts, recursive: true).get()

    let transcript = "{transcripts}/{run_id}.log"
    var agent = AgentRun(Usage(), 0.0, 0, false)

    if h.name() == "oracle":
        let src = reference_for(ch, lang)
        let size = stat(src, true).to_optional()
        create_directory(
            "{ws}/{lang.solution.split("/").take(lang.solution.split("/").length() - 1).join("/")}",
            recursive: true
        ).get()
        if size.is_some(): copy_file(src, "{ws}/{lang.solution}", replace: true).get()
    else:
        agent = run_agent(h, prompt, model, ws, timeout_s, transcript)

    let log = read_log(ws)

    # Cheap leak guard: flag runs whose transcript mentions the benchmark's own challenge tree.
    let said = read_text(transcript)
    let peeked = (
        said.contains("bench/agent/challenges")
        or said.contains("hidden/cases.json")
    )
    var g = grade(ch, lang, ws)
    let sol = "{ws}/{lang.solution}"

    if stat(sol, true).is_ok() and h.name() != "oracle":
        let copied = "{root()}/results/sources/{run_id}{lang.suffix()}"
        create_directory("{root()}/results/sources", recursive: true).get()
        copy_file(sol, copied, replace: true).get()
        g.llm_tokens = llm_tokens(sol)

    let rec = RunRecord(
        run_id.clone(), now().unix_seconds(), tag.clone(), ch.id.clone(),
        ch.category.clone(), ch.tier, lang.id.clone(), h.name(), model.clone(),
        agent.usage.clone(), agent.wall_s, agent.exit_code, agent.timed_out, log.builds,
        log.first_build_ok, log.checks, log.examples_pass, peeked, g.clone(), g.pass
    )
    append_file(out_file, dumps_data(rec, 0) + "\n").get()

    if keep:
        stdout().write("  workspace kept: {ws}\n").get()
    else:
        remove(base, recursive: true).get()

    return rec

type Job:
    challenge: Challenge
    language: Lang

# Runs every job in `items`, printing one verdict line each; returns how many failed.
fn work(items: List[Job], harness: String, o: Options, tag: String) Int:
    let h = find(harness).get()
    var bad = 0

    for item in items:
        let rec = run_one(
            item.challenge, item.language, h, o.model, o.timeout, o.keep, o.out, tag
        )

        let verdict = if rec.pass: "PASS" else: "FAIL"

        (
            stdout()
            .write(
                "{verdict} {item.challenge.id} {item.language.id} {rec.grade.passed}/{rec.grade.total} turns={rec.usage.turns} cost=${rec.usage.cost_usd.to_fixed(3)} {rec.wall_s}s\n"
            )
            .get()
        )
        if not rec.pass: bad += 1

    return bad

fn cmd_list(o: Options) Int!:
    for c in load_challenges([]):
        (
            stdout()
            .write(
                "{c.id.pad_end(28, " ")} {c.category.pad_end(14, " ")} tier {c.tier}\n"
            )
            .get()
        )
    (
        stdout().write(
            "languages: {load_languages([]).map(fn l: l.id.clone()).join(", ")}\n"
        ).get()
    )
    stdout().write("harnesses: {names().join(", ")}\n").get()
    return ok(0)

fn cmd_run(opts: Options, oracle: Bool) Int!:
    var o = opts.clone()

    if oracle:
        o.out = "{root()}/results/oracle.jsonl"
        remove(o.out, recursive: false).to_optional()

    let chs = load_challenges(split_ids(o.challenges))
    let langs = load_languages(split_ids(o.languages))
    let h = find(if oracle: "oracle" else: o.harness).get()
    var todo = List[Job]()

    for ch in chs:
        for lang in langs:
            if oracle and not stat(reference_for(ch, lang), true).is_ok():
                (
                    stdout()
                    .write(
                        "SKIP {ch.id} {lang.id} (no reference solution; cases come from the challenge's Go oracle)\n"
                    )
                    .get()
                )
                continue

            for _n in 0..(if oracle: 1 else: o.repeat):
                todo.append(Job(ch.clone(), lang.clone()))

    let jobs = if oracle: 1 else: if o.jobs < 1: 1 else: o.jobs

    let tag = if oracle: "oracle" else: o.tag.clone()

    var bad = 0
    var group = TaskGroup[Int]()

    for w in 0..jobs:
        let mine = todo.entries().filter(fn e: e.index % jobs == w).map(
            fn e: (e.value.clone())
        )
        let me = h.name()
        let own = o.clone()
        let label = tag.clone()
        group.spawn(fn _c: work(mine, me, own, label), none)

    for n in group.results().get([]): bad += n
    if oracle: remove(o.out, recursive: false).to_optional()
    return ok(if bad > 0 and oracle: 1 else: 0)

export fn main() Int:
    let flags = [
        Flag(
            "challenges", help: "comma list of ids or prefixes (default all)",
            default: ""
        ),
        Flag("languages", help: "comma list (default all)", default: "")
    ]
    let run_flags = flags.concat(
        [
            Flag("harness", required: true, choices: names()),
            Flag("model"),
            Flag("repeat", FlagKind.Int, default: "1"),
            Flag(
                "jobs", FlagKind.Int, help: "runs in parallel", default: "1"
            ),
            Flag(
                "timeout", FlagKind.Int, help: "agent wall-clock limit, seconds",
                default: "900"
            ),
            Flag("keep", FlagKind.Bool, help: "keep workspaces"),
            Flag(
                "tag", help: "free-form label stored with each run", default: ""
            ),
            Flag("out", default: "{root()}/results/runs.jsonl")
        ]
    )
    let root = Command(
        name: "run.ms",
        about: "Agent-effectiveness benchmark runner",
        children: [
            command[Options](
                name: "list", about: "list challenges and languages",
                run: fn o: cmd_list(o)
            ),
            command[Options](
                name: "run", about: "run agents on challenges", flags: run_flags,
                run: fn o: cmd_run(o, false)
            ),
            command[Options](
                name: "oracle",
                about: "run reference solutions through the grader (validates tests)",
                flags: flags, run: fn o: cmd_run(o, true)
            )
        ]
    )
    return root.execute(arguments())
