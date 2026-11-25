// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Command fixtures: records and replays `ms` commands that the conformance corpus does
// not cover (`lint`, `inspect`, `init`, ...).
//
// A fixture is a directory tests/conformance/commands/<command>/<name>/ holding
//   args        one argument per line (the command is the first line)
//   stdin       optional bytes fed to standard input
//   ignore      optional paths (one per line) left out of the compared tree
//   input/      files copied into a fresh working directory before the run
//   expected/   stdout, stderr, status, and tree/ (every file in the working directory
//               after the run)
// The working directory prints as <DIR>. MS names the ms under test (default
// .artifacts/build/ci/src/cli/ms). Recording runs the ms named by MS. Usage: ms run
// tools/command-fixtures.ms -- record|check [--only-missing] [name prefix ...] Prints
// `commands: passed/total` for `check`.
import (
	Bytes from "@std/bytes.ms",
	arguments, change_directory, working_directory from "@std/os/env.ms",
	CopyOptions,
	GlobOptions,
	access,
	copy,
	create_directory,
	glob,
	read_file,
	temporary,
	write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

fn text_of(data Bytes) String {
	return (data.decode_utf8() or "").clone()
}

// Replaces the working directory, spelled as the runtime names it or with
// forward slashes as ms prints it on Windows, with <DIR> and the digits after
// `"duration_ns": ` with 0, the only value that varies between runs.
fn normalize(text, dir String) String {
	marker := "\"duration_ns\": "
	slashed := dir.replace("\\", "/")
	parts := text.replace(dir, "<DIR>").replace(slashed, "<DIR>").split(marker)
	var out = parts[0].clone()

	for index in 1..parts.length() {
		rest := parts[index]
		var start = 0
		while (
			start < rest.length()
			and "0123456789".contains(rest.slice(start, start + 1))
		) {
			start += 1
		}
		out += marker + "0" + rest.slice(start, rest.length())
	}

	return out
}

// Every file under `root` as relative path then normalized content.
fn tree_of(root, dir String, ignored List[String]) Map[String, String] {
	var files = Map[String, String]()

	for found in glob(root, GlobOptions(patterns: ["**/*", "**/.*", "**/.*/**"])).get_or(
		[]
	) {
		path := f"{root}/{found.path}"
		if found.entry.directory { continue }
		if ignored.contains(found.path) { continue }

		// A macOS build writes the debug companion `<output>.dSYM/` beside an
		// executable with debug info; the recorded Linux runs have none.
		if found.path.contains(".dSYM/") { continue }

		files.add(
			found.path.clone(),
			normalize(text_of(read_file(path).wait().get()), dir),
		)
	}

	return files
}

fn write_text(path, text String) Void {
	write_file(path, text, replace: true).wait().get()
}

// The outcome of one case_dir run in a fresh working directory.
type Outcome {
	stdout, stderr String
	status Int
	files Map[String, String]
}

fn execute(ms, case_dir String) Outcome {
	scratch := temporary("ms-cmd-").get()
	work := f"{scratch.path()}/work"
	create_directory(work.clone()).get()
	if access(f"{case_dir}/input", 0).is_ok() {
		copy(
			f"{case_dir}/input",
			work.clone(),
			CopyOptions(recursive: true, replace: true),
		).get()
	}

	var ignored = List[String]()
	if access(f"{case_dir}/ignore", 0).is_ok() {
		for line in text_of(read_file(f"{case_dir}/ignore").wait().get()).split("\n") {
			if line != "" { ignored.append(line.clone()) }
		}
	}

	var input = "".to_bytes()
	if access(f"{case_dir}/stdin", 0).is_ok() {
		input = read_file(f"{case_dir}/stdin").wait().get()
	}

	var args = List[String]()
	for line in text_of(read_file(f"{case_dir}/args").wait().get()).split("\n") {
		if line != "" { args.append(line.clone()) }
	}

	out := run(
		ms.clone(),
		args,
		RunOptions(cwd: work.clone(), timeout: seconds(120), input: input),
	).wait().get()
	return Outcome(
		stdout: normalize(text_of(out.stdout), work),
		stderr: normalize(text_of(out.stderr), work),
		status: out.exit_code,
		files: tree_of(work, work, ignored),
	)
}

fn record(case_dir String, outcome Outcome) Void {
	expected := f"{case_dir}/expected"
	create_directory(f"{expected}/tree", recursive: true).get()
	write_text(f"{expected}/stdout", outcome.stdout)
	write_text(f"{expected}/stderr", outcome.stderr)
	write_text(f"{expected}/status", f"{outcome.status}\n")

	for item in outcome.files.entries() {
		path := item.key.clone()
		content := item.value.clone()
		parts := path.split("/")
		if parts.length() > 1 {
			create_directory(
				f"{expected}/tree/{path.slice(0, path.length() - parts[parts.length() - 1].length() - 1)}",
				recursive: true,
			).get()
		}
		write_text(f"{expected}/tree/{path}", content.clone())
	}
}

fn expected_text(case_dir, name String) String {
	return text_of(
		read_file(f"{case_dir}/expected/{name}").wait().get_or("".to_bytes())
	)
}

// `text` on one line, cut to 400 bytes, for a failure message.
fn brief(text String) String {
	flat := text.replace("\n", "\\n").replace("\r", "\\r")
	if flat.length() <= 400 { return flat }

	return flat.slice(0, 400) + "..."
}

// A failure message naming the stream and showing both texts.
fn stream_difference(stream, expected, observed String) String {
	return f"{stream} differs\n  expected: {brief(expected)}\n  observed: {brief(observed)}"
}

// The first difference between the recorded and the observed outcome, or "".
fn difference(case_dir String, outcome Outcome) String {
	stdout := expected_text(case_dir, "stdout")
	if stdout != outcome.stdout {
		return (
			stream_difference("stdout", stdout, outcome.stdout)
			+ f"\n  stderr: {brief(outcome.stderr)}"
		)
	}

	stderr := expected_text(case_dir, "stderr")
	if stderr != outcome.stderr {
		return stream_difference("stderr", stderr, outcome.stderr)
	}
	if expected_text(case_dir, "status") != f"{outcome.status}\n" { return f"status {outcome.status}" }

	tree := f"{case_dir}/expected/tree"
	var recorded = 0

	for found in glob(tree, GlobOptions(patterns: ["**/*", "**/.*", "**/.*/**"])).get_or(
		[]
	) {
		if found.entry.directory { continue }

		recorded += 1

		seen := outcome.files.get(found.path)
		if seen == null { return f"missing file {found.path}" }
		if text_of(read_file(f"{tree}/{found.path}").wait().get()) != seen { return f"file {found.path} differs" }
	}

	if recorded != outcome.files.length() {
		var extra = List[String]()
		for item in outcome.files.entries() {
			if access(f"{tree}/{item.key}", 0).is_error() {
				extra.append(item.key.clone())
			}
		}
		return f"extra files written: {extra.join(", ")}"
	}

	return ""
}

fn selected(case_dir String, prefixes List[String]) Bool {
	if prefixes.is_empty() { return true }

	for prefix in prefixes {
		if case_dir.contains(prefix) { return true }
	}
	return false
}

fn main() Int {
	root := working_directory().get()
	var words = List[String]()
	for word in arguments() {
		words.append(word.clone())
	}
	if words.is_empty() { return 64 }

	mode := words[0].clone()
	var only_missing = false
	var prefixes = List[String]()

	for word in words.slice(1, words.length()).get() {
		if word == "--only-missing" {
			only_missing = true
		} else {
			prefixes.append(word.clone())
		}
	}

	ms := tool_ms(root.clone())
	base := "tests/conformance/commands"
	var total = 0
	var passed = 0

	for found in glob(base, GlobOptions(patterns: ["*/*/args"])).get_or([]) {
		case_dir := f"{base}/{found.path.slice(0, found.path.length() - 5)}"
		if not selected(case_dir, prefixes) { continue }
		if (
			mode == "record"
			and only_missing
			and access(f"{case_dir}/expected/status", 0).is_ok()
		) { continue }

		total += 1

		outcome := execute(f"{ms}", f"{root}/{case_dir}")

		if mode == "record" {
			record(f"{root}/{case_dir}", outcome)

			// A second run must give the same answer, or the output is not
			// deterministic.
			again := execute(ms.clone(), f"{root}/{case_dir}")

			if difference(f"{root}/{case_dir}", again) != "" {
				print(f"NONDETERMINISTIC {case_dir}")
				continue
			}

			passed += 1
			continue
		}

		reason := difference(f"{root}/{case_dir}", outcome)

		if reason == "" {
			passed += 1
		} else {
			print(f"FAIL {case_dir}: {reason}")
		}
	}

	change_directory(root).get()
	print(f"commands: {passed}/{total}")
	if passed != total { return 1 }

	return 0
}
