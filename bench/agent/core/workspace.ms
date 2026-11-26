// ms: allow_effect std.clock.read
// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Build an agent workspace and score a finished one against hidden tests.
import (
	panic from "@std/core.ms",
	parse from "@std/data/json.ms",
	CopyOptions, access, chmod, copy, create_directory from "@std/os/fs.ms",

	bash, norm, read_text, write_text from "../lib/text.ms",
	count_workspace from "./codetokens.ms",
	Challenge, Lang, repo, root from "./model.ms",
)

// The benchmark's verdict on one finished workspace.
export type Grade {
	built Bool
	passed, total Int
	pass Bool
	code_tokens Int
	error String?
	failed List[String]?
	llm_tokens Int?
}

// Build counts the agent's own `./check.sh` runs left in `.bench/log.jsonl`.
export type BuildLog {
	builds Int
	first_build_ok Bool
	// The first build passed, or would have after the language's machine fixes
	// (`ms check --only types --fix`).
	first_build_fixed_ok Bool
	checks Int
	examples_pass Bool
	// Diagnostic codes seen in the agent's failed builds, one entry per occurrence.
	build_codes List[String]
	// The first diagnostic line of each failed build.
	build_errors List[String]
}

type LogRow {
	phase String
	ok Bool
	codes, msg, fixed String = ""
}

// Creates `dest` with the language template, spec, examples and `check.sh`. Returns the
// agent prompt.
export fn make_workspace(ch Challenge, lang Lang, dest String) String {
	create_directory(dest, recursive: true).get()
	copy(
		f"{root()}/templates/{lang.template}",
		dest,
		CopyOptions(recursive: true, replace: true),
	).get()

	// An edit challenge ships the program to change in `start/<language>/`.
	start := f"{ch.dir}/start/{lang.template}"
	is_edit := access(start, 0).is_ok()
	if is_edit { copy(start, dest, CopyOptions(recursive: true, replace: true)).get() }

	var n = 0

	for c in ch.cases("examples") {
		n += 1

		name := f"{n}".pad_start(2, "0")
		write_text(f"{dest}/examples/{name}.in", c.stdin)
		write_text(f"{dest}/examples/{name}.out", c.stdout)
	}

	write_text(f"{dest}/TASK.md", ch.spec())

	if not lang.setup.is_empty() {
		setup := bash(lang.setup, dest, 120, "")

		// A workspace without its skill would measure an agent that was never taught
		// the language, so a failed install stops the run instead of passing silently.
		if setup.code != 0 {
			panic(
				f"setup for {lang.name} failed (status {setup.code}): {setup.err}{setup.out}"
			)
		}
	}

	check := read_text(f"{root()}/check.sh.tmpl").replace(
		"{build}",
		lang.build,
	).replace("{run}", lang.run).replace("{codes}", lang.codes).replace(
		"{fix}",
		lang.fix,
	)
	write_text(f"{dest}/check.sh", check)
	chmod(f"{dest}/check.sh", 493).get()
	for ctx in lang.context {
		if ctx.starts_with("@repo/") {
			copy(
				f"{repo()}/{ctx.slice(6, ctx.length())}",
				f"{dest}/docs",
				CopyOptions(recursive: true, replace: true),
			).get()
		}
	}

	task := (
		if is_edit { f"{lang.solution} already holds a working {lang.name} program; change it as TASK.md describes, keeping every behavior TASK.md does not change. " } else { f"Implement the program described in TASK.md in {lang.name}. " }
	)
	return (
		task
		+ f"Edit {lang.solution}; it reads stdin and writes stdout. "
		+ "Run ./check.sh to build and test against the examples in examples/. "
		+ "The final grading uses additional hidden cases of the same format, so handle the edge cases the spec describes. "
		+ f"{lang.notes} Work autonomously and stop when the program is correct."
	)
}

// Reads the build and check counts the workspace's `./check.sh` logged.
export fn read_log(ws String) BuildLog {
	var rows = List[LogRow]()

	for line in read_text(f"{ws}/.bench/log.jsonl").split("\n") {
		if line.trim().is_empty() { continue }

		rows.append(parse[LogRow](line).get_or(LogRow("", false, "", "", "")))
	}

	builds := rows.filter(r => r.phase == "build")
	checks := rows.filter(r => r.phase == "check")
	var first_ok = false
	first := builds.first()
	if first != null { first_ok = first.ok }

	var fixed_ok = first_ok
	first := builds.first()
	if first != null { fixed_ok = first.ok or first.fixed == "true" }

	var last_ok = false
	last := checks.last()
	if last != null { last_ok = last.ok }

	var codes = List[String]()
	var errors = List[String]()

	for failed in builds.filter(r => not r.ok) {
		if not failed.msg.is_empty() {
			errors.append(failed.msg.clone())
		}
		for code in failed.codes.split(" ") {
			if not code.is_empty() { codes.append(code.clone()) }
		}
	}

	return BuildLog(
		builds.length(),
		first_ok,
		fixed_ok,
		checks.length(),
		last_ok,
		codes,
		errors,
	)
}

// Builds the workspace's solution and runs the hidden cases.
export fn grade(ch Challenge, lang Lang, ws String) Grade {
	cases := ch.cases("hidden")
	tokens := count_workspace(ws, lang.suffix())
	built := bash(lang.build, ws, 600, "")

	if built.code != 0 {
		tail := built.err.slice(
			if built.err.length() > 500 { built.err.length() - 500 } else { 0 },
			built.err.length(),
		)
		return Grade(
			built: false,
			passed: 0,
			total: cases.length(),
			pass: false,
			error: tail,
			failed: null,
			code_tokens: tokens,
			llm_tokens: null,
		)
	}

	var passed = 0
	var failed = List[String]()

	for c in cases {
		ran := bash(lang.run, ws, ch.timeout_s, c.stdin)

		if ran.code == 0 and norm(ran.out) == norm(c.stdout) {
			passed += 1
		} else {
			failed.append(c.name.clone())
		}
	}

	return Grade(
		built: true,
		passed: passed,
		total: cases.length(),
		pass: passed == cases.length(),
		error: null,
		failed: failed.take(10),
		code_tokens: tokens,
		llm_tokens: null,
	)
}
