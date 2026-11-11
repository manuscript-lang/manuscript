// Build an agent workspace and score a finished one against hidden tests.
import (
	parse from "@std/data/json.ms",
	CopyOptions, chmod, copy, create_directory from "@std/os/fs.ms",

	bash, norm, read_text, write_text from "../lib/text.ms",
	count_workspace from "./codetokens.ms",
	Challenge, Lang, repo, root from "./model.ms",
)

// The benchmark's verdict on one finished workspace.
export type Grade:
	built: Bool
	passed: Int
	total: Int
	pass: Bool
	error: String?
	failed: List[String]?
	code_tokens: Int
	llm_tokens: Int?

// Build counts the agent's own `./check.sh` runs left in `.bench/log.jsonl`.
export type BuildLog:
	builds: Int
	first_build_ok: Bool
	checks: Int
	examples_pass: Bool

type LogRow:
	phase: String
	ok: Bool

// Creates `dest` with the language template, spec, examples and `check.sh`. Returns the
// agent prompt.
export fn make_workspace(ch: Challenge, lang: Lang, dest: String) String:
	create_directory(dest, recursive: true).get()
	copy(
		"{root()}/templates/{lang.template}",
		dest,
		CopyOptions(recursive: true, replace: true),
	).get()

	var n = 0

	for c in ch.cases("examples"):
		n += 1

		name := "{n}".pad_start(2, "0")
		write_text("{dest}/examples/{name}.in", c.stdin)
		write_text("{dest}/examples/{name}.out", c.stdout)

	write_text("{dest}/TASK.md", ch.spec())

	check := read_text("{root()}/check.sh.tmpl").replace(
		"\{build\}",
		lang.build,
	).replace("\{run\}", lang.run)
	write_text("{dest}/check.sh", check)
	chmod("{dest}/check.sh", 493).get()
	for ctx in lang.context:
		if ctx.starts_with("@repo/"):
			copy(
				"{repo()}/{ctx.slice(6, ctx.length()).get("")}",
				"{dest}/docs",
				CopyOptions(recursive: true, replace: true),
			).get()
	return (
		"Implement the program described in TASK.md in {lang.name}. "
		+ "Edit {lang.solution}; it reads stdin and writes stdout. "
		+ "Run ./check.sh to build and test against the examples in examples/. "
		+ "The final grading uses additional hidden cases of the same format, so handle the edge cases the spec describes. "
		+ "{lang.notes} Work autonomously and stop when the program is correct."
	)

// Reads the build and check counts the workspace's `./check.sh` logged.
export fn read_log(ws: String) BuildLog:
	var rows = List[LogRow]()

	for line in read_text("{ws}/.bench/log.jsonl").split("\n"):
		if line.trim().is_empty(): continue

		rows.append(parse[LogRow](line).get(LogRow("", false)))

	builds := rows.filter(fn r: r.phase == "build")
	checks := rows.filter(fn r: r.phase == "check")
	var first_ok = false
	if first := builds.first(): first_ok = first.ok

	var last_ok = false
	if last := checks.last(): last_ok = last.ok
	return BuildLog(builds.length(), first_ok, checks.length(), last_ok)

// Builds the workspace's solution and runs the hidden cases.
export fn grade(ch: Challenge, lang: Lang, ws: String) Grade:
	cases := ch.cases("hidden")
	tokens := count_workspace(ws, lang.suffix())
	built := bash(lang.build, ws, 600, "")

	if built.code != 0:
		tail := built.err.slice(
			if built.err.length() > 500: built.err.length() - 500 else: 0,
			built.err.length(),
		).get("")
		return Grade(false, 0, cases.length(), false, tail, none, tokens, none)

	var passed = 0
	var failed = List[String]()

	for c in cases:
		ran := bash(lang.run, ws, ch.timeout_s, c.stdin)

		if ran.code == 0 and norm(ran.out) == norm(c.stdout):
			passed += 1
		else:
			failed.append(c.name.clone())

	return Grade(
		true,
		passed,
		cases.length(),
		passed == cases.length(),
		none,
		failed.take(10),
		tokens,
		none,
	)
