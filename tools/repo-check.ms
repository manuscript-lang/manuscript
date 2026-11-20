// Repository invariants that no compiler or test run enforces (`make repo-check`). Run
// from the repository root with libms's tool entry points linked:
//   ms run tools/repo-check.ms --link target/libms_tools.a [-- licenses [-check]]
// Exits nonzero listing every violation. The rules live in tools/repo-check/.
import (
	JsonValue, parse from "@std/data/json.ms",
	arguments from "@std/os/env.ms",
	exists from "@std/os/fs.ms",
	SpawnOptions, Stdio, run from "@std/os/process.ms",

	capture, env, exe, note, tool_ms from "./lib.ms",
	calendar_version,
	extension_version,
	workflow_triggers from "./repo-check/checks_release.ms",
	inline_source, stages from "./repo-check/checks_rust.ms",
	impl_adjacency,
	nested,
	optional_defaults,
	standard_syntax,
	stream_names from "./repo-check/checks_syntax.ms",
	cancel_jumps,
	internal_externs,
	layering,
	portability,
	thread_affinity,
	timed_waits,
	unsafe_boundary from "./repo-check/checks_text.ms",
	licenses from "./repo-check/licenses.ms",
	skill_manifests,
	skill_mistakes,
	skill_pages,
	skill_server_state from "./repo-check/skill.ms",
	skipped from "./repo-check/util.ms",
)

// Tracked and untracked-but-not-ignored files that still exist, `/`-separated.
fn tracked_files() List[String]:
	listing := capture(
		"git",
		[
			"-c", "core.quotepath=off", "ls-files", "--cached", "--others",
			"--exclude-standard", "--deduplicate"
		],
	)
	var files = List[String]()
	for path in listing.lines():
		if not path.is_empty() and exists(path).get_or(false): files.append(
			path.clone()
		)
	return files

// `ms fmt --check` over the repository's own sources; crate test inputs deliberately keep their
// original spelling, and recorded agent solutions are evidence that stays as the agent
// wrote it. A file that does not parse is a negative fixture; the nested-match and test
// suites own it.
fn format_drift(files: List[String]) List[String]:
	var candidates = List[String]()

	for path in files:
		if not path.ends_with(".ms") or skipped(path): continue
		if path.contains("/tests/") or path.starts_with("bench/agent/results/sources/"): continue

		candidates.append(path.clone())

	var issues = List[String]()
	ms := tool_ms(".")

	for batch in candidates.chunks(200):
		args := ["fmt", "--check", "--json", "--"].concat(batch)
		out := run(ms, args).wait()

		if finished := out:
			doc := parse(finished.stdout.decode_utf8().get_or("")).get_or(
				JsonValue.Null
			)
			entries := doc.get("files").get_or(JsonValue.Null).as_list().get_or([])

			for entry in entries:
				if (
					entry.get("status").get_or(
						JsonValue.Null
					).as_string().get_or("") == "needs_formatting"
				):
					path := entry.get("path").get_or(
						JsonValue.Null
					).as_string().get_or("")
					issues.append(f"{path}: run ms fmt")
		else:
			issues.append("format check: cannot run " + ms)

	return issues

fn main() Int:
	args := arguments()

	if args.length() > 0:
		if args == ["licenses"] or args == ["licenses", "-check"]:
			why := licenses(args.length() == 2)
			if why.is_empty(): return 0

			note(why)
			return 1

		note("usage: repo-check [licenses [-check]]")
		return 2

	files := tracked_files()
	var issues = List[String]()
	issues.extend(standard_syntax())
	issues.extend(nested(files))
	issues.extend(format_drift(files))
	issues.extend(extension_version())
	issues.extend(calendar_version())
	issues.extend(workflow_triggers())
	issues.extend(unsafe_boundary(files))
	issues.extend(inline_source(files))
	issues.extend(portability(files))
	issues.extend(stream_names(files))
	issues.extend(impl_adjacency(files))
	issues.extend(internal_externs(files))
	issues.extend(optional_defaults(files))
	issues.extend(layering(files))
	issues.extend(stages(files))
	issues.extend(thread_affinity(files))
	issues.extend(cancel_jumps(files))
	issues.extend(timed_waits(files))
	issues.extend(skill_pages())
	issues.extend(skill_server_state())
	issues.extend(skill_mistakes())
	issues.extend(skill_manifests())

	if issues.is_empty():
		print(
			"Nested matches, formatting, stdlib syntax, release pins, triggers, unsafe boundary, inline sources, portability, stream names, impl adjacency, internal externs, optional defaults, crate layering, checker stage layering, thread affinity, cancel by return, timed waits, and the agent skill agree."
		)
		return 0

	issues.sort()
	note("repository invariants:\n- " + issues.join("\n- "))
	return 1
