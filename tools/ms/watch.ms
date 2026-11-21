// `--watch` of `ms check`, `lint`, `test` and `run`: run the command once, then again
// after each saved change to the input, its manifest or a module it imports. A failed
// run only reports; the previous program of `run` keeps going until a replacement
// builds.
//
// Each run is this command line again without `--watch`, so the C checks, the test
// runner and the Rust commands answer exactly as they do without it. The files to watch
// are read from the sources themselves: every `from "./path.ms"` of the input and of
// what it imports, the nearest
// `ms.toml`, and the files of its project. A path that does not exist yet is watched too, so
// creating it reruns the command.
import (
	TomlValue, parse from "@std/data/toml.ms",
	stderr from "@std/io/io.ms",
	environment from "@std/os/env.ms",
	canonicalize,
	exists,
	list,
	read_file,
	remove,
	stat,
	temporary_directory from "@std/os/fs.ms",
	dirname, join, normalize from "@std/os/path.ms",
	SpawnOptions,
	Stdio,
	Subprocess,
	process_info,
	send_signal,
	spawn,
	watch_signals from "@std/os/process.ms",
	milliseconds, monotonic from "@std/time.ms",

	Invocation from "./args.ms",
	DiscoverError from "./fmt.ms",
	lex, token_kind from "./syntax.ms",
)

extern fn ms_tool_discover(target: String) List[String]!DiscoverError

// How often the watched files are looked at, and how long a run waits after the last
// change it saw, in milliseconds.
POLL_MS := 10
SETTLE_POLLS := 1
// A replaced program gets this long to finish its cleanup before it is killed.
GRACE_MS := 5000
// The exit status of a command stopped by SIGINT or SIGTERM.
STOPPED := 130
SIGINT := 2

fn note(text: String) Void:
	void stderr().write(text + "\n")

// ---- the files a run depends on ----

// What `path` looks like now: a signature that changes when its content, kind, mode or
// identity does, and `missing` when nothing is there.
export fn signature(path: String) String:
	info := stat(path)
	if info.is_error(): return "missing"

	found := info.get()
	modified := found.modified.to_string()
	return f"{found.size}:{modified}:{found.mode}:{found.inode}:{found.device}"

// The module paths `text` imports from its own directory or through an alias of
// `aliases` (`@name` to an absolute path): each `from "./x.ms"`, `from "../x.ms"` and
// `from "@name/x.ms"`. A package or standard-library import is not local and is left
// out.
export fn local_imports(
	text: String,
	directory: String,
	aliases: Map[String, String],
) List[String]:
	tokens := lex(text)
	if tokens.is_error(): return []

	string_kind := token_kind("STRING")
	var found = List[String]()
	var at = 0

	while at + 1 < tokens.get().length():
		first := tokens.get()[at].clone()
		second := tokens.get()[at + 1].clone()
		at += 1
		if second.kind != string_kind or text.slice(first.lo, first.hi) != "from": continue

		spelled := text.slice(second.lo + 1, second.hi - 1)

		if spelled.starts_with("./") or spelled.starts_with("../"):
			found.append(normalize(join([directory.clone(), spelled])))
		else if target := aliased(spelled, aliases):
			found.append(target)

	return found

// The path `spelled` (`@name` or `@name/rest`) names through `aliases`, or none.
fn aliased(spelled: String, aliases: Map[String, String]) String?:
	if not spelled.starts_with("@"): return none

	slash := spelled.index_of("/").get_or(spelled.length())
	root := aliases.get(spelled.slice(0, slash))?
	if slash == spelled.length(): return root.clone()

	return normalize(join([root.clone(), spelled.slice(slash + 1, spelled.length())]))

// The nearest `ms.toml` above `start`, or none.
fn nearest_manifest(start: String) String?:
	var directory = dirname(start)

	while true:
		candidate := join([directory.clone(), "ms.toml"])
		if exists(candidate).get_or(false): return candidate

		parent := dirname(directory)
		if parent == directory: return none

		directory = parent

	return none

// The path of `input` as a complete path, so the files it names compare equal however
// the command spelled it.
fn complete(input: String) String:
	return canonicalize(input).get_or(input.clone())

// What the manifest at `manifest` adds to the module graph: the alias targets, and the
// paths that change the build without being imported: embedded directories and member
// projects.
type Manifest:
	aliases: Map[String, String]
	embedded: List[String]
	members: List[String]

// The table `key` of a parsed manifest, empty when it has none.
fn table_at(document: TomlValue, key: String) Map[String, TomlValue]:
	var none_found = Map[String, TomlValue]()

	match document:
		TableValue(values):
			found := values.get(key)
			if found.is_none(): return none_found
			match found.get():
				TableValue(inner): return inner.clone()
				_: return none_found
		_: return none_found

// The text of a manifest value, or the empty text.
fn text_of(value: TomlValue) String:
	match value:
		StringValue(text): return text.clone()
		_: return ""

// The text under `key` of the table `value`, or the empty text.
fn field(value: TomlValue, key: String) String:
	match value:
		TableValue(values):
			found := values.get(key)
			return if found.is_some(): text_of(found.get()) else: ""
		_: return ""

// Reads `manifest`; a missing or invalid one describes nothing.
fn read_manifest(manifest: String) Manifest:
	var read = Manifest(aliases: Map[String, String](), embedded: [], members: [])
	bytes := read_file(manifest).wait()
	if bytes.is_error(): return read

	document := parse(bytes.get().decode_utf8().get_or(""))
	if document.is_error(): return read

	root := dirname(manifest)

	for entry in table_at(document.get(), "aliases"):
		{key, value} := entry
		read.aliases.add(key.clone(), normalize(join([root.clone(), text_of(value)])))

	for entry in table_at(document.get(), "embed"):
		read.embedded.append(normalize(join([root.clone(), text_of(entry.value)])))

	for entry in table_at(document.get(), "dependencies"):
		member := field(entry.value, "path")
		if not member.is_empty(): read.members.append(
			normalize(join([root.clone(), member, "ms.toml"]))
		)

	return read

// The directory `path` and everything below it.
fn tree(path: String) List[String]:
	var found = [path.clone()]
	var pending = [path.clone()]
	var at = 0

	while at < pending.length():
		current := pending[at].clone()
		at += 1

		entries := list(current)
		if entries.is_error(): continue

		for entry in entries.get():
			child := join([current.clone(), entry.name.clone()])
			found.append(child.clone())
			if entry.directory: pending.append(child.clone())

	return found

// Every file whose change reruns `input`: the module graph read from the sources, the
// manifest and lock file, the files of its project and of its member projects, embedded
// directories, and the directories that hold them.
export fn watched_files(input: String) List[String]:
	start := complete(input)
	var seen = Map[String, Bool]()
	var order = List[String]()
	var queue = [start.clone()]
	var aliases = Map[String, String]()
	var at = 0
	var manifest: String? = none

	if input.ends_with("ms.toml"): manifest = start.clone()
	else: manifest = nearest_manifest(start)

	if found := manifest:
		if input.ends_with("ms.toml"): queue = []
		order.append(found.clone())
		order.append(join([dirname(found), "ms.lock"]))
		seen.add(found.clone(), true)

		read := read_manifest(found)
		aliases = read.aliases.clone()
		for file in discovered(found): queue.append(file.clone())
		for path in read.embedded: order.extend(tree(path))

		for member in read.members:
			order.append(member.clone())
			for file in discovered(member): queue.append(file.clone())

	while at < queue.length():
		path := queue[at].clone()
		at += 1
		if seen.contains(path): continue

		seen.add(path.clone(), true)
		order.append(path.clone())

		directory := dirname(path)

		if not seen.contains(directory):
			seen.add(directory.clone(), true)
			order.append(directory)

		bytes := read_file(path).wait()
		if bytes.is_error(): continue

		for next in local_imports(
			bytes.get().decode_utf8().get_or(""),
			dirname(path),
			aliases,
		):
			queue.append(next.clone())

	return order

// The source files of the project `manifest` describes; none when the reader does not
// cover it.
fn discovered(manifest: String) List[String]:
	got := ms_tool_discover(manifest)
	if got.is_error(): return []

	return got.get()

// The files of every input of the command.
fn watched_inputs(inv: Invocation) List[String]:
	var files = List[String]()
	var seen = Map[String, Bool]()
	inputs := if inv.targets.is_empty(): [inv.filename.clone()] else: inv.targets.clone()

	for input in inputs:
		for path in watched_files(input):
			if seen.contains(path): continue

			seen.add(path.clone(), true)
			files.append(path.clone())

	return files

// The signature of every watched path.
fn snapshot(paths: List[String]) Map[String, String]:
	var states = Map[String, String]()
	for path in paths: states.add(path.clone(), signature(path))
	return states

// The states of the same paths now, when any of them no longer looks the way `before`
// recorded it; none when nothing changed.
fn poll(before: Map[String, String]) Map[String, String]?:
	var now = Map[String, String]()
	var differs = false

	for entry in before:
		{key, value} := entry
		current := signature(key)
		if current != value: differs = true
		now.add(key.clone(), current)

	return if differs: now else: none

// ---- the command lines ----

// The words of this run: the command line without `--watch`.
export fn once_arguments(given: List[String]) List[String]:
	return given.filter(fn word: word != "--watch")

// The command line that builds `run`'s program into `executable`: `build`, the options
// of the run, and no program arguments.
export fn build_arguments(given: List[String], executable: String) List[String]:
	var words = List[String]()
	var program_arguments = false

	for word in once_arguments(given):
		if word == "--": program_arguments = true
		if program_arguments: continue

		words.append(if word == "run": "build" else: word.clone())

	words.append("-o")
	words.append(executable.clone())
	return words

// ---- the loop ----

// The command runs to its end, inheriting this command's streams; its exit status.
fn run_to_end(program: String, words: List[String]) Int:
	child := spawn(
		program,
		words,
		SpawnOptions(
			stdin: Stdio.Inherit,
			stdout: Stdio.Inherit,
			stderr: Stdio.Inherit,
		),
	)

	if child.is_error():
		note(f"ms: cannot run {program}")
		return 70

	return child.get().wait().get_or(70)

// `check`, `lint` and `test`: the command again after each change.
fn watch_once(inv: Invocation, given: List[String]) Int:
	program := process_info().get().executable
	words := once_arguments(given)
	var signals = watch_signals([SIGINT, 15], none).get()
	var states = Map[String, String]()
	var waiting = 0
	var due = true

	while true:
		if due:
			states = snapshot(watched_inputs(inv))
			void run_to_end(program, words)
			note("ms: waiting for changes")
			due = false

		got := signals.next(milliseconds(POLL_MS))
		if got.is_ok(): return STOPPED

		if next := poll(states):
			states = next
			waiting = SETTLE_POLLS
		else if waiting > 0:
			waiting -= 1
			if waiting == 0: due = true

	return 0

// `run`: build, start the program, and replace it with the next build after each change.
fn watch_run(inv: Invocation, given: List[String]) Int:
	program := process_info().get().executable
	directory := temporary_directory("manuscript-watch-").get_or("")
	var signals = watch_signals([SIGINT, 15], none).get()
	var states = Map[String, String]()
	var running: Subprocess? = none
	var executable = ""
	var generation = 0
	var reason = "started"
	var waiting = 0
	var due = true
	var since = monotonic()

	while true:
		if due:
			states = snapshot(watched_inputs(inv))
			generation += 1

			next := join([directory.clone(), f"program-{generation}"])
			status := run_to_end(program, build_arguments(given, next))

			if status == 0:
				if old := running:
					stop(old)
					running = none

				if not executable.is_empty(): void remove(executable)
				executable = next.clone()

				started := spawn(
					executable,
					inv.arguments,
					SpawnOptions(
						stdin: Stdio.Inherit,
						stdout: Stdio.Inherit,
						stderr: Stdio.Inherit,
					),
				)

				if started.is_error(): note(f"ms: cannot run {executable}")
				else:
					note(
						f"ms: {reason} run in {monotonic().difference(since).to_milliseconds()} ms"
					)
					running = started.get()
			else:
				note("ms: waiting for changes")

			reason = "restarted"
			due = false

		got := signals.next(milliseconds(POLL_MS))

		if got.is_ok():
			if old := running: stop(old)
			if not executable.is_empty(): void remove(executable)
			return STOPPED

		if live := running:
			ended := live.wait(milliseconds(1))

			if ended.is_ok():
				note(f"ms: exited with status {ended.get()}; waiting for changes")
				running = none

		if next := poll(states):
			if waiting == 0: since = monotonic()
			states = next
			waiting = SETTLE_POLLS
		else if waiting > 0:
			waiting -= 1
			if waiting == 0: due = true

	return 0

// Interrupts `child` and gives it the grace period to finish; then it is killed.
fn stop(child: Subprocess) Void:
	void send_signal(child.pid(), SIGINT)

	ended := child.wait(milliseconds(GRACE_MS))
	if ended.is_error(): child.kill()

// The exit status of `--watch`, which only a signal ends.
export fn run_watch(inv: Invocation, given: List[String]) Int:
	if inv.command == "run": return watch_run(inv, given)
	return watch_once(inv, given)
