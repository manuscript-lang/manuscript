// `ms review` orchestration: reads a unified diff, maps it onto the project, rebuilds the
// base text of each changed source from the head tree, and prints the report or the
// explanation. Port of `diff_inputs` and `review_input` in
// crates/ms-cli/src/engine/tooling.rs.
//
// The facts of the head and of the rebuilt base come from `facts_command`: a program
// run as
// `PROGRAM facts FILE` in the project directory, printing the facts JSON (`ms-tooling-dev`
// today, the C checker's dump once its columns match; see tools/ms/facts_diff.ms).
import (
	BytesBuilder from "@std/bytes.ms",
	parse from "@std/data/json.ms",
	stderr, stdin, stdout from "@std/io/io.ms",
	arguments, environment from "@std/os/env.ms",
	GlobOptions,
	canonicalize,
	create_directory,
	exists,
	glob,
	read_file,
	temporary,
	write_file from "@std/os/fs.ms",
	basename, dirname, join, relative from "@std/os/path.ms",
	RunOptions, run from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	DiffFile, parse_diff, reverse_apply from "./diff.ms",
	explain, explain_json from "./mark.ms",
	DiffStats, ReviewOptions, diff_report, project_report, render from "./report.ms",
	DiffInput, compare_facts from "./review.ms",
	Facts from "./views.ms",
)

// What a diff means for one project: the change summary, the counts the report prints,
// and the rebuilt base text of every changed source that existed before
// (project-relative).
export type Plan:
	input: DiffInput
	stats: DiffStats
	base: Map[String, String]

fn changed_lines(file: DiffFile) DiffStats:
	var stats = DiffStats()

	for hunk in file.hunks:
		for line in hunk.lines:
			if line.starts_with("+"): stats.insertions += 1
			else if line.starts_with("-"): stats.deletions += 1

	return stats

// `path` relative to `prefix` (the project's directory inside the checkout, `""` for the
// checkout itself), or none when it lies outside.
fn inside(prefix: String, path: String) String?:
	if prefix.is_empty(): return path.clone()
	if not path.starts_with(f"{prefix}/"): return none

	return path.slice(prefix.length() + 1, path.length())

/*
Maps `diff` onto the project. `heads` holds the current text of each source named by a
non-deleted file of the diff, keyed by the diff's path; `present` names the diff paths of
deleted sources that still exist. Only `.ms` files inside the project take part.
*/
export fn plan_review(
	diff: List[DiffFile],
	prefix: String,
	heads: Map[String, String],
	present: Set[String],
) Plan!:
	var plan = Plan(
		input: DiffInput(
			added: Set[String](),
			touched: Map[String, List[Int]](),
			base_checked: false,
		),
		stats: DiffStats(files: diff.length()),
		base: Map[String, String](),
	)

	for file in diff:
		counted := changed_lines(file)
		plan.stats.insertions += counted.insertions
		plan.stats.deletions += counted.deletions

		path := file.path()
		if not path.ends_with(".ms"): continue

		relative := inside(prefix, path)
		if relative.is_none(): continue

		name := relative.get()
		plan.stats.sources += 1

		if file.new.is_empty():
			if present.contains(path): return error(
				Error(
					f"{path}: deleted source still exists in the working tree"
				)
			)

			text := reverse_apply("", file.hunks)?
			plan.base.add(name, text)
			continue

		head := heads.get(path)
		if head.is_none(): return error(
			Error(f"{path}: the source is not in the working tree")
		)

		base := reverse_apply(head.get(), file.hunks)?

		if file.old.is_empty():
			if not base.is_empty(): return error(
				Error(
					f"{path}: added source diff does not cover the whole file"
				)
			)

			plan.input.added.add(name.clone())
		else:
			plan.base.add(name.clone(), base)

		plan.input.touched.add(name, file.touched_lines())

	return ok(plan)

// What `ms review` was asked.
export type ReviewRequest:
	file: String
	diff: String = ""
	format: String = "ascii"
	all: Bool = false
	effect: String = ""
	explain: String = ""

// The program that prints the facts JSON, run as `PROGRAM facts FILE`.
fn facts_program() String:
	env := environment().get_or(Map[String, String]())
	return env.get_or("MS_FACTS", "ms-tooling-dev")

fn facts_in(directory: String, file: String) Facts!:
	finished := run(
		facts_program(),
		["facts", file.clone()],
		RunOptions(cwd: directory.clone()),
	).wait()?
	text := finished.stdout.decode_utf8().get_or("")

	if finished.exit_code != 0:
		detail := finished.stderr.decode_utf8().get_or("")
		return error(Error(f"{file}: the program does not check:\n{detail}"))

	return ok(parse[Facts](text)?)

fn read_text(path: String) String!:
	return ok(read_file(path).wait()?.decode_utf8().get_or(""))

fn read_diff(path: String) String!:
	if path != "-": return read_text(path)

	var input = stdin()
	var builder = BytesBuilder()

	while true:
		chunk := input.next()?
		if chunk.is_none(): break

		builder.append_bytes(chunk.get())

	return ok(builder.build().decode_utf8().get_or(""))

// The directory above `root` (or `root` itself) that holds the diff's first source, and
// `root`'s path from it: the diff names paths from the checkout's top.
fn prefix_of(root: String, diff: List[DiffFile]) String:
	for file in diff:
		if not file.path().ends_with(".ms") or file.new.is_empty(): continue

		var directory = root.clone()

		while true:
			if exists(join([directory.clone(), file.path()])).get_or(false):
				return relative(directory, root).get_or("")

			parent := dirname(directory)
			if parent == directory: return ""

			directory = parent

	return ""

// Copies the project's sources and manifests beside the base text of the changed ones.
fn base_tree(root: String, base: Map[String, String], target: String) Void!:
	patterns := ["**/*.ms", "**/ms.toml", "**/ms.lock"]
	found := glob(
		root,
		GlobOptions(patterns: patterns, exclude: ["**/target/", "**/.git/"]),
	)?

	for entry in found:
		if entry.entry.directory: continue

		text := read_text(join([root.clone(), entry.path.clone()]))?
		destination := join([target.clone(), entry.path.clone()])
		create_parent(destination)?
		write_file(destination, text, replace: true).wait()?

	for name in base.keys():
		destination := join([target.clone(), name.clone()])
		create_parent(destination)?
		write_file(destination, base.get_or(name, ""), replace: true).wait()?

	return ok()

fn create_parent(path: String) Void!:
	return create_directory(dirname(path), recursive: true)

/*
Runs `ms review`: the project map without a diff, otherwise the change report or the
explanation of one finding. The text goes to the caller; an error is a problem to report
with status 2.
*/
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.env.read
// ms: allow_effect std.console.read
export fn review(request: ReviewRequest) String!:
	json := request.format == "json"
	options := ReviewOptions(all: request.all or json, effect: request.effect.clone())
	absolute := canonicalize(request.file)?
	root := dirname(absolute)
	name := basename(absolute)
	head := facts_in(root.clone(), name.clone())?
	if request.diff.is_empty(): return ok(
		render(project_report(head, options), request.format)
	)

	parsed := parse_diff(read_diff(request.diff)?)?
	prefix := prefix_of(root, parsed)
	var heads = Map[String, String]()
	var present = Set[String]()

	for file in parsed:
		path := file.path()
		if not path.ends_with(".ms"): continue

		inside_root := inside(prefix, path)
		if inside_root.is_none(): continue

		source := join([root.clone(), inside_root.get()])

		if file.new.is_empty():
			if exists(source).get_or(false): present.add(path.clone())
			continue

		heads.add(path.clone(), read_text(source)?)

	var plan = plan_review(parsed, prefix, heads, present)?
	scratch := temporary("ms-review-")?
	base_tree(root, plan.base, scratch.path())?

	base := facts_in(scratch.path(), name)
	if base.is_ok(): plan.input.base_checked = true

	baseline := base.get_or(Facts(entities: [], imports: [], flows: []))

	if not request.explain.is_empty():
		findings := compare_facts(baseline, head, plan.input)
		if json: return ok(explain_json(findings, head, request.explain)?.concat("\n"))

		return explain(findings, head, request.explain)

	return ok(
		render(
			diff_report(baseline, head, plan.input, plan.stats, options),
			request.format,
		)
	)

fn usage() Error:
	return Error(
		"usage: review_cmd.ms FILE [--diff PATCH|-] [--format ascii|markdown|json] [--all] [--effect NAME] [--explain ID]"
	)

// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.env.read
// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Int:
	args := arguments()
	var request = ReviewRequest(file: "")
	var i = 0

	while i < args.length():
		option := args[i].clone()
		i += 1

		if option == "--all": request.all = true
		else if option == "--diff":
			request.diff = args.get_or(i, "")
			i += 1
		else if option == "--format":
			request.format = args.get_or(i, "")
			i += 1
		else if option == "--effect":
			request.effect = args.get_or(i, "")
			i += 1
		else if option == "--explain":
			request.explain = args.get_or(i, "")
			i += 1
		else if option.starts_with("--") or not request.file.is_empty():
			stderr().write(usage().message + "\n").get()
			return 2
		else: request.file = option

	if request.file.is_empty():
		stderr().write(usage().message + "\n").get()
		return 2

	printed := review(request)

	if printed.is_error():
		stderr().write(f"ms review: {printed.err().message}\n").get()
		return 2

	var out = stdout()
	out.write(printed.get()).get()
	out.flush().get()
	return 0

test "a diff that adds, edits and deletes sources maps onto the project":
	patch := "diff --git a/lib/a.ms b/lib/a.ms\nnew file mode 100644\n--- /dev/null\n+++ b/lib/a.ms\n@@ -0,0 +1,2 @@\n+export fn a() Int:\n+    return 1\ndiff --git a/lib/b.ms b/lib/b.ms\n--- a/lib/b.ms\n+++ b/lib/b.ms\n@@ -1,2 +1,2 @@\n export fn b() Int:\n-    return 1\n+    return 2\ndiff --git a/other/c.ms b/other/c.ms\n--- a/other/c.ms\n+++ b/other/c.ms\n@@ -1 +1 @@\n-old\n+new\n"
	parsed := parse_diff(patch).get()
	heads := {
		"lib/a.ms": "export fn a() Int:\n    return 1\n",
		"lib/b.ms": "export fn b() Int:\n    return 2\n"
	}
	plan := plan_review(parsed, "lib", heads, Set[String]()).get()
	expect_equal(plan.stats.files, 3)?
	expect_equal(plan.stats.sources, 2)?
	expect_equal(plan.stats.insertions, 4)?
	expect_equal(plan.stats.deletions, 2)?
	expect_true(plan.input.added.contains("a.ms"))?
	expect_equal(plan.base.get("b.ms").get(), "export fn b() Int:\n    return 1\n")?
	expect_equal(plan.base.contains("a.ms"), false)?
	expect_equal(plan.input.touched.get("b.ms").get(), [2, 2])?

test "a deleted source that still exists is refused":
	patch := "diff --git a/d.ms b/d.ms\ndeleted file mode 100644\n--- a/d.ms\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n"
	parsed := parse_diff(patch).get()
	refused := plan_review(parsed, "", Map[String, String](), ["d.ms"].to_set())
	expect_true(refused.is_error())?

test "an added source whose diff leaves earlier text is refused":
	patch := "diff --git a/n.ms b/n.ms\nnew file mode 100644\n--- /dev/null\n+++ b/n.ms\n@@ -1 +1,2 @@\n+added\n kept\n"
	parsed := parse_diff(patch).get()
	refused := plan_review(parsed, "", {"n.ms": "added\nkept\n"}, Set[String]())
	expect_true(refused.is_error())?
