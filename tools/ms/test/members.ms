// `ms test` on several manifests, or on a workspace root: each manifest is its own
// program with its own tests, so they run one after another as this command line again,
// and the worst status wins. `--json` holds one result per manifest.
import (
	JsonValue, parse from "@std/data/json.ms",
	stderr, stdout from "@std/io/io.ms",
	RunOptions, SpawnOptions, Stdio, process_info, run, spawn from "@std/os/process.ms",

	Invocation from "../args.ms",
	flag, list_of, number, object, render_document, text, with from "../json_out.ms",
)

// The arguments of one manifest's run: the command and every argument that is not one
// of the original targets, with the manifest first.
fn member_arguments(args: List[String], inv: Invocation, manifest: String) List[String]:
	var rest = List[String]()
	var targets = inv.targets.clone()

	for given in args.drop(1):
		at := targets.index_of(given)

		if at.is_some():
			targets.remove(at.get())
			continue

		rest.append(given.clone())

	var out = [args[0].clone(), manifest.clone()]
	out.extend(rest)
	return out

export fn run_members(args: List[String], inv: Invocation, manifests: List[String]) Int:
	info := process_info()

	if info.is_error():
		stderr().write(info.err().message + "\n").get()
		return 1

	executable := info.get().executable.clone()
	var status = 0
	var results = List[JsonValue]()

	for manifest in manifests:
		given := member_arguments(args, inv, manifest)

		if not inv.structured:
			stderr().write(f"ms: testing {manifest}\n").get()

			started := spawn(
				executable.clone(),
				given,
				SpawnOptions(
					stdin: Stdio.Inherit,
					stdout: Stdio.Inherit,
					stderr: Stdio.Inherit,
				),
			)
			var code = 1

			if started.is_ok():
				var child = started.get()
				code = child.wait().get_or(1)

			if code > status: status = code
			continue

		finished := run(executable.clone(), given, RunOptions()).wait()
		var code = 1
		var document: JsonValue = JsonValue.Null
		var errors = ""

		if finished.is_ok():
			code = finished.get().exit_code
			errors = finished.get().stderr.decode_utf8().get_or("")

			parsed := parse(finished.get().stdout.decode_utf8().get_or(""))
			if parsed.is_ok(): document = parsed.get()

		if code > status: status = code

		var item = object()
		item = with(item, "target", text(manifest))
		item = with(item, "exit_code", number(code))
		item = with(item, "document", document)
		item = with(item, "stderr", text(errors))
		results.append(item)

	if inv.structured:
		stdout().write(
			render_document(with(object(), "results", list_of(results)))
		).get()
	return status
